# Deploy to drewdettmer.com/fallout

Caddy combines the game container’s labels with the existing site block. The more specific `/fallout/*` handler forwards to nginx. The **Fallout Forecast Web** Coolify app rebuilds from `master` through the GitHub App push webhook. GitHub Actions verifies the ARM64 Dockerfile and keeps the build artifact.

```powershell
gh run list --workflow web-export.yml --branch master --limit 1
curl.exe -fsSI https://drewdettmer.com/fallout
curl.exe -fsS https://drewdettmer.com/fallout/healthz
```

## Recreate the Coolify resource

Make sure the Coolify GitHub App installation includes `kickofline/fallout-forecast`. Use the same `master` revision for the browser build and dedicated server.

From Drew’s Tailnet-connected Windows workstation, start a PowerShell session with the Coolify environment. Approve the 1Password prompt when it appears.

```powershell
op run --environment fat7y6e344e32zyeajda6akclq -- powershell -NoLogo -NoProfile
```

Run the following inside that session. It reuses a matching app if creation already succeeded.

```powershell
$ErrorActionPreference = 'Stop'
if (-not $env:COOLIFY_ACCESS_TOKEN) { throw 'Coolify environment is missing' }

function Invoke-Coolify($Method, $Path, $RequestBody) {
    $request = @{
        Uri = "https://ballista.west-alpha.ts.net/api/v1$Path"
        Method = $Method
        Headers = @{ Authorization = "Bearer $env:COOLIFY_ACCESS_TOKEN" }
    }
    if ($null -ne $RequestBody) {
        $request.ContentType = 'application/json'
        $request.Body = ConvertTo-Json $RequestBody -Depth 8
    }
    Invoke-RestMethod @request
}

$gameApps = @((Invoke-Coolify GET /applications) | Where-Object { $_.name -eq 'Fallout Forecast Web' })
if ($gameApps.Count -gt 1) { throw 'Resolve the duplicate game apps before proceeding' }
if ($gameApps.Count -eq 1) {
    if ($gameApps[0].git_repository -ne 'kickofline/fallout-forecast' -or $gameApps[0].git_branch -ne 'master') {
        throw 'The existing app has a different repository or branch'
    }
    $appId = $gameApps[0].uuid
} else {
    $gameApp = Invoke-Coolify POST /applications/private-github-app @{
        name = 'Fallout Forecast Web'
        project_uuid = 'ms004o480cgcwckww80wcs0g'
        environment_uuid = 'kwsgcos00oc0gw4og8osokkk'
        server_uuid = 'jkwg4cwowssgk8ckg8884ss0'
        destination_uuid = 'doww80cw8kc8844w4gcs88s0'
        github_app_uuid = 'k0o84oowooog8ksk04cg8ocs'
        git_repository = 'kickofline/fallout-forecast'
        git_branch = 'master'
        build_pack = 'dockerfile'
        base_directory = '/'
        dockerfile_location = '/web/Dockerfile'
        ports_exposes = '8080'
        autogenerate_domain = $false
        instant_deploy = $false
        is_auto_deploy_enabled = $false
        is_preview_deployments_enabled = $false
    }
    $appId = $gameApp.uuid
}
if (-not $appId) { throw 'Coolify did not return an app UUID' }
Write-Output "Fallout Forecast Web UUID = $appId"

$labels = @'
caddy_ingress_network=coolify
caddy_0=https://drewdettmer.com
caddy_0.redir=/fallout /fallout/ 308
caddy_0.handle_path=/fallout/*
caddy_0.handle_path.0_reverse_proxy={{upstreams 8080}}
'@

Invoke-Coolify PATCH "/applications/$appId" @{
    is_container_label_readonly_enabled = $false
    custom_labels = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(($labels -replace "`r`n", "`n")))
    health_check_enabled = $true
    health_check_path = '/healthz'
    health_check_port = '8080'
    health_check_scheme = 'http'
} | Out-Null

Invoke-Coolify POST "/deploy?uuid=$appId&force=false" | Select-Object -ExpandProperty deployments
```

Check the deployment until it finishes.

```powershell
(Invoke-Coolify GET "/deployments/applications/${appId}?take=1").deployments |
    Select-Object deployment_uuid, status, commit, is_webhook
```

Then verify the homepage, redirect, game launcher and health endpoint. Open the game in Chromium or Firefox, start a solo run, and join the cloud lobby through **Join Game**. The browser and the dedicated server must use compatible `Net.PROTOCOL` values.

```powershell
curl.exe -fsSI https://drewdettmer.com/
curl.exe -fsSI https://drewdettmer.com/courses
curl.exe -fsSI https://drewdettmer.com/fallout
curl.exe -fsSI https://drewdettmer.com/fallout/
curl.exe -fsS https://drewdettmer.com/fallout/healthz
```

## Enable production push deploys

Run this in the same 1Password session after the production check passes. The next push to `master` starts the production build.

```powershell
Invoke-Coolify PATCH "/applications/$appId" @{
    git_branch = 'master'
    is_auto_deploy_enabled = $true
} | Select-Object uuid, name, git_branch
```

On the next push, confirm the new deployment has `is_webhook` set. Repeat the live browser and homepage checks against that deployment. To take down only the game, use **Stop** on the **Fallout Forecast Web** app in Coolify.
