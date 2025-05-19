# Solution: K3s Service Restart Issue

## Problem Description

The K3s service was failing to start with the following error:

```
time="2025-05-18T14:02:26+02:00" level=fatal msg="no-deploy flag is deprecated. Use --disable instead."
```

This error occurred because the K3s configuration was using a deprecated flag format.

## Root Cause

The issue was in the format of the `--disable` flag in the K3s configuration. The error message indicates that the format has changed, and the correct format should use an equals sign (`--disable=traefik`) instead of a space (`--disable traefik`).

## Changes Made

1. Updated the K3s server arguments in the Ansible playbook:
   - File: `lions-infrastructure\ansible\playbooks\install-k3s.yml`
   - Changed from: `--disable traefik` to `--disable=traefik`

2. Updated the documentation to reflect the correct flag format:
   - File: `lions-infrastructure\docs\guides\vps-deployment.md`
   - Changed from: `--disable traefik --disable servicelb` to `--disable=traefik --disable=servicelb`

## Expected Outcome

With these changes, the K3s service should now start successfully without the "no-deploy flag is deprecated" error. The service will properly disable the specified components (traefik and servicelb where applicable) using the correct flag format.

## Additional Notes

This issue was caused by a change in the K3s command-line interface where the format of the `--disable` flag was updated. The error message provided clear guidance on how to update the flag format, which made the solution straightforward to implement.