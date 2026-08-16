---
name: debug-jenkins-container-deploy
description: "Use when a Jenkins/CI redeploy reports success but a containerized service still uses old config, missing files, or unset environment variables."
auto-generated: true
generated-at: 2026-08-14T01:34:22.467Z
source-task: "jenkins reinstall success, but still not works\r\n[09:19:03] 诊断: TRACY_ENABLED=<unset> · livestream=not-running — 容器内未启用 Tracy：.env 需 TRACY_ENABLED=true 并重建容器; Isaac Sim 未在运行，需先启动 WebRTC livestream; 容器…"
---
## When to use
- A pipeline rerun is marked successful, but the service behavior is unchanged.
- Errors such as `executable file not found`, missing environment variables, or old files persist across reruns.
- The Jenkins job supports selective stages, refresh flags, or skip flags that may cause only part of the deployment to run.
- A container image or service was modified, but the running container does not reflect those modifications.

## Steps
1. Inspect the pipeline and deploy scripts to find early-exit or skip logic. Trace exactly which stages run for the selected Jenkins parameters.
2. Separate the failure into deployment layers:
   - **Environment variable unset:** the container must be recreated with the new `-e`, `--env-file`, or compose environment; rebuilding the image alone is not enough.
   - **Script/file missing inside the container:** the Dockerfile must `COPY` or install the file and the image must be rebuilt; recreating a container from an old image keeps the file missing.
   - **Binary/tool missing:** verify whether the installed package variant is headless, slim, or minimal; it may omit GUI/CLI tools even when protocol ports are available. Install the standalone tool or required package separately if needed.
3. Identify which previous reruns were ineffective because a refresh flag rebuilt only an unrelated component or caused the target stage to be skipped.
4. Run the target deployment stage with the parameter combination that reaches both image rebuild and container recreation for the affected service. Disable unrelated short-circuit flags and do not skip the target stage.
5. After deployment, verify directly inside the running container:
   - `docker exec <container> env | grep <VARIABLE>`
   - `docker exec <container> ls -l /path/to/file`
   - `docker exec <container> command -v <tool>`
   - `docker inspect <container>` or `docker history <image>` to confirm image/container creation.
6. If the diagnostic depends on another service being active, start or verify that service first, then rerun the failing operation.

## Pitfalls
- A frontend or web-viewer refresh flag may exit before rebuilding the backend container.
- Rebuilding an image does not automatically replace an existing container.
- Recreating a container does not automatically rebuild its image.
- Repeated identical diagnostics usually mean the fix never reached the running container, not that the fix logic itself is wrong.
- Headless extension packages may omit profiler GUI/CLI binaries while still exposing the profiling protocol port.
- Do not assume `docker run` changes are applied until the container is actually removed and recreated.

## Example
A profiler command failed with `tracy-control: not found`, `TRACY_ENABLED=<unset>`, and a missing `tracy-capture` binary after multiple Jenkins reruns. The reruns had rebuilt only the web viewer, so the Isaac container and image were untouched. The complete fix was to copy the control script into the image, pass `TRACY_ENABLED=true` during container creation, add a fallback that downloads the standalone capture CLI for headless containers, and rerun the target stage with both image rebuild and container recreate flags enabled while disabling the unrelated viewer refresh flag.
