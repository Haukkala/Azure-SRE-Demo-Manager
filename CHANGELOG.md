# Changelog

Infrastructure and Bicep fixes made to this project, in chronological order. This covers
`infrastructure/` only — see `infrastructure/DEPLOYMENT_CHANGES.md` for the same history with full
root-cause writeups, and `infrastructure/README.md` for current parameters/troubleshooting.

## 2026-07-15

### Removed plaintext admin password from the tracked parameters file
`infrastructure/main.parameters.json` had `adminPassword` committed in plaintext. Rotated the
credential directly on the live Madrid VM (`az vm user update`), then removed the value from the
tracked file entirely — `deploy.sh` already prompts for it interactively and passes it as a
separate `--parameters` override, so the file never needed to carry it.
*The old password remains visible in earlier git history (commit `848787c`) — this was a deliberate
decision to leave history as-is rather than rewrite it (`git filter-repo`/BFG + force-push), not an
oversight. The credential itself is no longer valid.*
Commit: `3bec967`

### Moved the frontend App Service to westeurope (northeurope quota block)
Every App Service Plan tier tried in `northeurope` (Basic B1, Free F1, Premium v3 P0v3, Premium v3
P1v3) failed identically with `InternalSubscriptionIsOverQuotaForSku`. Confirmed region-specific
(not SKU-specific) by deploying the identical plan successfully in `westeurope`; a self-service
`Microsoft.Quota` increase request was submitted and denied (`QuotaNotAvailableForResource`). Added
a separate `frontendLocation` parameter (default `westeurope`) so only the frontend module deploys
there — everything else stays in `northeurope`.
Commits: `7ebeb4a`, `1eb18d7`, `02b1213`

### Fixed Container Apps environments sharing a subnet
Lisbon, Berlin, and Chaos Control each provision their own Container Apps managed environment, all
originally bound to the same `snet-container-apps` subnet. Azure does not allow multiple
environments to share a subnet (confirmed via three identical `ManagedEnvironmentSubnetInUse`
failures even with dependency serialization). Gave each its own dedicated subnet:
`snet-lisbon-apps`, `snet-berlin-apps`, `snet-berlin-mcp-apps` (Chaos Control kept
`snet-container-apps`).
Commit: `1015e66`

### Fixed AcrPull role-assignment name collision
`acr-role-assignment.bicep` named its role assignment `guid(acr.id, 'AcrPull')` — identical for
every caller regardless of identity. Only the first of five callers (Lisbon, Berlin, Chaos Control,
VM Health Control, Berlin MCP) ever actually got `AcrPull`; the rest failed with
`RoleAssignmentUpdateNotPermitted`. Fixed by including `principalId` in the `guid()` seed.
Commit: `bd0ed4b`

### Stopped registering ACR credentials for images that aren't hosted there
Every container-app module built a `registries` block whenever `containerRegistry` was non-empty,
regardless of whether `containerImage` was actually hosted on it. With the placeholder
`mcr.microsoft.com` image and `createContainerRegistry=true`, every container app was told to
authenticate to ACR via an identity that didn't have `AcrPull` yet (that's granted by a *separate*
module that runs afterward) — this stalled revision provisioning indefinitely. Fixed by only
including the registries entry when `containerImage` actually starts with `containerRegistry`.
Commit: `244a06d`

### Removed custom health probes that hung revision provisioning
Custom `httpGet` liveness/readiness probes against the placeholder image caused the Container Apps
revision controller to hang indefinitely rather than just report unhealthy — confirmed with a
direct `az containerapp create` test with no probes succeeding instantly against the same
image/environment. Removed the probes for now (`TODO` comments mark where to restore `/health`
probes once real application images are deployed).
Commits: `2be8f2d`, `2f59c5f`

### Added a NAT gateway to the container-apps subnet
Defense-in-depth outbound connectivity fix — turned out not to be the actual blocker for image
pulls (Consumption-plan Container Apps environments provision their own platform-managed outbound
IP), but left in place since it doesn't hurt.
Commit: `3d2624c`

## 2026-07-14

### vnet API-version update that fixed the persistent subnet-recreate bug
Root cause of the recurring `InUseSubnetCannotBeDeleted` failure on every redeploy: the vnet
resource never declared the vnet-wide `privateEndpointVNetPolicies` property, and API version
`2023-05-01` doesn't even support it in the Bicep type schema. Every vnet PUT silently reset it to
the provider default, and Azure re-evaluates private-endpoint policy across *every* subnet in the
vnet atomically when this changes — requiring all attached NICs/private endpoints in any subnet to
be momentarily detachable, which surfaced as `InUseSubnetCannotBeDeleted` on whichever resource
happened to be attached. Fixed by bumping the vnet resource to API version `2024-05-01` and
explicitly declaring `privateEndpointVNetPolicies: 'Disabled'`.
Commit: `9226ae6` (preceded by the equivalent per-subnet fix in `e64aede`, which was necessary but
not sufficient on its own)

### Fixed Paris/Madrid VM NIC ignoring the deployVM flag
`paris-api.bicep` and `madrid-api.bicep` created each VM's network interface with no
`if (deployVM)` guard, unlike the VM resource and its extensions. With `deployParisVm=false`,
`nic-paris-vm` was still created every deployment, permanently occupying an IP config on
`snet-vms` even though the VM itself never existed. Gated the NIC on `deployVM` in both modules;
the orphaned `nic-paris-vm` (no VM ever attached) was deleted manually.
Commit: `c17f73c`

### Split Madrid/Paris DCR association into separate DCE and DCR resources
Azure Monitor requires the association name `configurationAccessEndpoint` to be used exclusively
for a data-collection-*endpoint* association — it can't also carry a `dataCollectionRuleId`. Split
each VM's single association into a dedicated endpoint association and a dedicated rule
association, chained with `dependsOn` so the endpoint attaches first.
Commit: `c8a6aeb` (superseding an earlier, incomplete attempt at the same fix in `ccd9d01`)

## 2026-07-10

### Region switch to North Europe + Madrid VM size fix
Switched the deployment region from `swedencentral` to `northeurope`, and changed the Madrid VM
size from `Standard_B2s` to `Standard_D2s_v3` after hitting `SkuNotAvailable` for B2s in this
region.
Commit: `5245257`

### NSG attached to the container-apps subnet
`snet-container-apps` had no Network Security Group, tripping the tenant's
`Deny-Subnet-Without-Nsg` Azure Policy. Attached `nsgAppService` to the subnet.
Commit: `aeb80db`
