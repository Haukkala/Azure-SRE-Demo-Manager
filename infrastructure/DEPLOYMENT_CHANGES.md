# Deployment Changes Summary

## Recent Changes

### July 15, 2026 - Fixed persistent InUseSubnetCannotBeDeleted and full end-to-end deployment failures

**Status:** `./deploy.sh` now completes with zero failed resources. Verified: hub, Madrid VM,
Berlin, Lisbon, Chaos Control, VM Health Control all `Succeeded`/`Running`. Paris stays
intentionally undeployed (`deployParisVm: false`). Frontend deploys to **westeurope** (see below),
everything else stays in `northeurope`.

**Issue:** Every redeploy to an already-provisioned environment failed with
`InUseSubnetCannotBeDeleted` on `snet-vms`, blocked by whatever happened to be attached (a private
endpoint, or a VM's NIC) - a genuinely different, deeper bug than the one described in the February
13 entry below, which only fixed a *different* subnet-recreate pattern (inline vs. child-resource
subnets). Once that was fixed, five more distinct bugs surfaced one at a time, each only reachable
after the previous one was resolved.

**Root causes and fixes, in the order they were found:**

1. **Subnet policy drift (the actual InUseSubnetCannotBeDeleted cause).** None of the hub subnets
   declared `privateEndpointNetworkPolicies`, and the vnet resource itself never declared the
   vnet-wide `privateEndpointVNetPolicies`. Azure's subnet/vnet PUT treats `properties` as a full
   replace, so every redeploy silently asked Azure to reset both back to their provider defaults -
   even though `snet-vms` hosts a private endpoint that requires them `Disabled`, and they were
   already `Disabled` live. Toggling that policy while anything is attached to any subnet in the
   vnet can't be done as an in-place patch, which surfaced as `InUseSubnetCannotBeDeleted` on
   whichever attached resource happened to be in the way. Fixed by declaring both explicitly on
   every subnet in `hub.bicep` and `github-runner-network.bicep`, and bumping the vnet resource to
   API version `2024-05-01` (`privateEndpointVNetPolicies` isn't in the `2023-05-01` type schema).

2. **Unconditional VM NICs.** `paris-api.bicep` and `madrid-api.bicep` created each VM's NIC with no
   `if (deployVM)` guard, unlike the VM resource and its extensions. With `deployParisVm: false`,
   `nic-paris-vm` was still created every deploy, permanently occupying an IP config on `snet-vms`.
   Fixed by gating the NIC on `deployVM` in both modules; the orphaned `nic-paris-vm` was deleted
   manually since no VM was ever attached to it.

3. **Placeholder image vs. app-specific ports/probes.** None of the container image parameters are
   overridden in `main.parameters.json`, so Lisbon/Berlin/Chaos Control all still run the default
   `mcr.microsoft.com/azuredocs/containerapps-helloworld` image (port 80, no `/health`), while each
   module's `ingress.targetPort` and liveness/readiness `httpGet` probes pointed at the real app's
   future port and `/health`. The probes never passed, and (separately) simply having custom
   `httpGet` probes at all caused the revision controller to hang indefinitely rather than just
   report unhealthy - confirmed by a direct `az containerapp create` with no probes succeeding
   instantly against the same image/environment. Probes were removed for now (each has a `TODO`
   marking where to restore `/health`-based probes once real images are pushed).

4. **ACR role-assignment name collision.** `acr-role-assignment.bicep` named its role assignment
   `guid(acr.id, 'AcrPull')` - identical for every caller regardless of identity. All five callers
   (Lisbon, Berlin, Chaos Control, VM Health Control, Berlin MCP) computed the same resource name,
   so only the first to deploy actually got `AcrPull`; the rest failed with
   `RoleAssignmentUpdateNotPermitted`. Fixed by including `principalId` in the `guid()` seed.

5. **Container Apps environments cannot share a subnet.** Lisbon, Berlin, and Chaos Control each
   provision their own managed environment, all originally pointed at `snet-container-apps`. This
   is a hard Azure platform limit (confirmed with three identical `ManagedEnvironmentSubnetInUse`
   failures even with dependency serialization) - not a race condition, not a sizing issue. Fixed
   by giving each its own dedicated subnet in `hub.bicep`: `snet-lisbon-apps` (`10.0.6.0/24`),
   `snet-berlin-apps` (`10.0.7.0/24`), `snet-berlin-mcp-apps` (`10.0.8.0/24`, for the currently
   disabled Berlin MCP module). Chaos Control kept `snet-container-apps` unchanged.

6. **App Service has a hard 0-quota block in `northeurope` on this subscription.** Every tier tried
   (Basic B1, Free F1, Premium v3 P0v3, Premium v3 P1v3) failed identically with
   `InternalSubscriptionIsOverQuotaForSku`, even where the Microsoft.Web usages API reported
   available cores. Confirmed region-specific (not SKU-specific) by successfully creating the
   identical P1v3 Linux plan instantly in `westeurope`. A self-service quota increase request via
   the `Microsoft.Quota` API for App Service `B1` in `northeurope` was submitted and **denied**
   (`QuotaNotAvailableForResource`) - this region appears to have a hard regional cap on App Service
   VM capacity for this subscription that isn't self-service adjustable; a manual Azure support
   ticket (with subscription support-plan-appropriate severity) would be the next step if
   consolidating everything into `northeurope` is ever required. For now, added a separate
   `frontendLocation` param (default `westeurope`) and pointed only the frontend module there -
   every other resource stays in `location` (`northeurope`). This is fully valid: resources within
   a resource group can each target any region independently of the resource group's own location.
   Reverted the App Service Plan to Basic B1 (cost-appropriate) once the real blocker was fixed.

**Also fixed, unrelated but adjacent:**
- `main.parameters.json` had the VM admin password committed in plaintext. Rotated the credential
  directly on the live Madrid VM via `az vm user update`, then removed the value from the tracked
  file entirely - `deploy.sh` already prompts for it interactively and overrides whatever's in the
  file, so it never needed to be stored there.
- Split each VM's DCR/DCE association into two separate resources (`vm-dcr-association.bicep`,
  `main.bicep`) - Azure Monitor requires the name `configurationAccessEndpoint` to be used
  exclusively for the endpoint association, not combined with a `dataCollectionRuleId`.
- Gave `snet-container-apps` a NAT gateway (shared with the runner subnet) for defense-in-depth
  outbound connectivity, though this turned out not to be the actual blocker for image pulls
  (Consumption-plan environments provision their own platform-managed outbound IP regardless).

**Files Modified:** `main.bicep`, `main.parameters.json`, `modules/hub.bicep`,
`modules/github-runner-network.bicep`, `modules/madrid-api.bicep`, `modules/paris-api.bicep`,
`modules/vm-dcr-association.bicep`, `modules/lisbon-api.bicep`, `modules/berlin-api.bicep`,
`modules/chaos-control.bicep`, `modules/vm-health-control.bicep`, `modules/berlin-mcp-server.bicep`,
`modules/acr-role-assignment.bicep`, `modules/frontend.bicep`.

**Teardown / redeploy for next time:**
```bash
# Teardown (see the "Cleaning Up" section below for the full command list)
az group delete --name rg-parking-hub-dev     --yes --no-wait
# ...and so on for every rg-parking-*-dev group

# Redeploy - all fixes above are baked into the templates, no manual steps needed
cd infrastructure
./deploy.sh
```
A from-scratch deploy should hit none of the manual-intervention steps this session needed (those
were all one-time cleanups of state left over from the *unfixed* bugs). The only interactive input
`deploy.sh` asks for is the new VM admin password and a yes/no confirmation.

---

### February 13, 2026 - Fixed VNet Subnet Management and Deployment Warnings

**Issue:** Infrastructure redeployments were failing with `InUseSubnetCannotBeDeleted` error for the `snet-github-runners` subnet, plus several Bicep warnings (BCP318, no-hardcoded-env-urls).

**Root Cause:** 
1. VNet resource in `hub.bicep` was defining subnets inline in the `subnets` array
2. During redeployment, Azure attempted to reconcile the VNet state and tried to delete subnets not in the inline array
3. The `snet-github-runners` subnet (created by `github-runner-network.bicep`) couldn't be deleted due to its GitHub Actions service association link
4. Conditional resources accessed without null-forgiving operators caused BCP318 warnings
5. Hardcoded `core.windows.net` URL prevented multi-cloud compatibility

**Solution:**
1. **Changed VNet subnet management approach:**
   - Removed inline `subnets` array from VNet resource definition in `hub.bicep`
   - Created all subnets as separate child resources: `snet-vms`, `snet-container-apps`, `snet-app-service`
   - Added proper dependencies between subnets for sequential creation
   - Updated outputs to reference subnet resources directly instead of using array indices
   - This prevents Azure from attempting to delete subnets during redeployment

2. **Fixed BCP318 null-safety warnings:**
   - Added null-forgiving operator `!` for VM resource access in `madrid-api.bicep` outputs
   - Added null-forgiving operator `!` for VM resource access in `paris-api.bicep` outputs
   - Added null-forgiving operator `!` for githubRunners module access in `main.bicep` outputs

3. **Fixed hardcoded environment URL:**
   - Changed from `privatelink.blob.core.windows.net` to `privatelink.blob.${environment().suffixes.storage}` in `storage-private-endpoint.bicep`
   - Now compatible with Azure Government, Azure China, and other sovereign clouds

**Impact:**
- Redeployments now work correctly without subnet deletion conflicts
- All Bicep warnings resolved - clean build with no errors or warnings
- Infrastructure is now multi-cloud compatible
- No changes required to parameters or deployment process
- Fully backward compatible with existing deployments

**Files Modified:**
- `infrastructure/modules/hub.bicep` - VNet subnet management refactoring
- `infrastructure/modules/madrid-api.bicep` - Null-forgiving operators in outputs
- `infrastructure/modules/paris-api.bicep` - Null-forgiving operators in outputs
- `infrastructure/modules/storage-private-endpoint.bicep` - Environment-aware DNS zone name
- `infrastructure/main.bicep` - Null-forgiving operator for githubRunners module output

---

### February 2026 - Fixed GitHub Runners Subnet Deployment Conflict

**Issue:** Infrastructure redeployments were failing with `InUseSubnetCannotBeDeleted` error for the `snet-github-runners` subnet.

**Root Cause:** The subnet was being created in two places:
1. `hub.bicep` - without GitHub delegation
2. `github-runner-network.bicep` - with proper GitHub delegation

This caused conflicts when redeploying because the subnet had a service association link from GitHub Actions that couldn't be deleted.

**Solution:**
- Removed the duplicate subnet creation from `hub.bicep`
- The subnet is now only created in `github-runner-network.bicep` with proper `GitHub.Network/networkSettings` delegation
- Added `natGatewayId` parameter to `github-runner-network.bicep` for proper outbound connectivity
- Updated `hub.bicep` to output the NAT Gateway ID
- Updated `main.bicep` to pass the NAT Gateway ID to the GitHub runner network module

**Impact:**
- Redeployments now work correctly without manual intervention
- No changes required to parameters or deployment process
- The fix is backward compatible with existing deployments

---

## Overview
This document outlines the changes made to the infrastructure deployment process to:
1. Use the `main.parameters.json` file for deployment configuration
2. Add a private Azure Container Registry (ACR) to the infrastructure

## Changes Made

### 1. Updated deploy.sh Script
The deployment script now uses the `main.parameters.json` file instead of prompting for all parameters interactively.

**Key Changes:**
- Checks for the existence of `main.parameters.json` before proceeding
- Reads location from the parameters file
- Only prompts for the admin password (for security reasons - passwords should not be stored in parameter files)
- Uses `--parameters "@main.parameters.json"` in the Azure CLI deployment commands
- Simplified validation and deployment commands

**Security Note:** The admin password is still required to be entered at runtime and is not stored in the parameters file.

### 2. Added Container Registry Module
Created a new Bicep module: `modules/container-registry.bicep`

**Features:**
- Creates an Azure Container Registry with a unique name
- Supports Basic, Standard, and Premium SKUs
- Admin user enabled by default for easy authentication
- Includes proper outputs for registry name, login server, and URL
- Follows Azure best practices for container registry configuration

### 3. Updated main.bicep
Integrated the Container Registry into the main infrastructure template.

**Changes:**
- Added `createContainerRegistry` parameter (default: true) to optionally create ACR
- Added `containerRegistrySku` parameter to choose the registry tier
- Created a new resource group for the container registry
- Added ACR module deployment with conditional creation
- Added new outputs for container registry information:
  - `containerRegistryName`
  - `containerRegistryLoginServer` 
  - `containerRegistryUrl`

### 4. Updated main.parameters.json
Added new parameters for container registry configuration:

```json
"createContainerRegistry": {
  "value": true
},
"containerRegistrySku": {
  "value": "Basic"
}
```

## How to Use

### Deploying with the New Configuration

1. **Edit the parameters file:**
   ```bash
   cd infrastructure
   nano main.parameters.json
   ```
   
   Update values as needed:
   - `location`: Your preferred Azure region
   - `environment`: dev, test, or prod
   - `adminUsername`: VM administrator username
   - `createContainerRegistry`: Set to `true` to create ACR, `false` to skip
   - `containerRegistrySku`: Choose Basic, Standard, or Premium

2. **Run the deployment:**
   ```bash
   ./deploy.sh
   ```
   
   You will only be prompted for:
   - Admin password (for VMs)
   - Confirmation to proceed

3. **After deployment:**
   The script will output the Container Registry details including:
   - Registry name
   - Login server URL
   - Access credentials

### Using the Container Registry

After deployment, you can:

1. **Login to the registry:**
   ```bash
   az acr login --name <registry-name>
   ```

2. **Get credentials:**
   ```bash
   az acr credential show --name <registry-name>
   ```

3. **Push images:**
   ```bash
   docker tag myimage:latest <registry-name>.azurecr.io/myimage:latest
   docker push <registry-name>.azurecr.io/myimage:latest
   ```

4. **Update Container Apps or VMs to use the private registry:**
   - Use the registry login server URL
   - Configure with admin credentials or managed identity

## Resource Groups Created

The deployment now creates the following resource groups:
- `rg-parking-hub-{environment}` - Networking and Log Analytics
- `rg-parking-frontend-{environment}` - Frontend App Service
- `rg-parking-lisbon-{environment}` - Lisbon Container App
- `rg-parking-madrid-{environment}` - Madrid Windows VM
- `rg-parking-paris-{environment}` - Paris Linux VM
- `rg-parking-registry-{environment}` - **NEW** Azure Container Registry

## Container Registry Naming

The ACR name is automatically generated as:
```
acrparking{environment}{uniqueString}
```

For example: `acrparkingdevxyz123abc`

This ensures global uniqueness as ACR names must be unique across all of Azure.

## Cost Considerations

**Basic SKU:**
- Suitable for development and testing
- 10 GB storage included
- Limited throughput

**Standard SKU:**
- Recommended for production workloads
- 100 GB storage included
- Better performance

**Premium SKU:**
- Advanced features (geo-replication, private link)
- 500 GB storage included
- Best performance

For development environments, Basic SKU is recommended to minimize costs.

## Next Steps

1. Push your container images to the new private registry
2. Update the `lisbonContainerImage` parameter to use images from your private registry
3. Consider configuring managed identity for Container Apps to access the registry without passwords
4. Set up retention policies and security scanning in the Azure Portal

## Rollback

To disable the container registry creation:
1. Edit `main.parameters.json`
2. Set `"createContainerRegistry": { "value": false }`
3. Redeploy

The existing registry will remain but won't be managed by future deployments.
