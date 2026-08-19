# Copy to _packer/hcloud.auto.pkrvars.hcl and adjust as needed.
# This keeps Packer and Terraform aligned on Talos release.

talos_version = "v1.13.9"

# Optional: override image factory URLs (for custom schematic/extensions)
# image_url_arm = "https://factory.talos.dev/image/<SCHEMATIC_ID>/v1.13.9/hcloud-arm64.raw.xz"
# image_url_x86 = "https://factory.talos.dev/image/<SCHEMATIC_ID>/v1.13.9/hcloud-amd64.raw.xz"
