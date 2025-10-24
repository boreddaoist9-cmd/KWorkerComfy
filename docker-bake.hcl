variable "DOCKERHUB_REPO" {
  default = "runpod"
}

variable "DOCKERHUB_IMG" {
  default = "worker-comfyui"
}

variable "RELEASE_VERSION" {
  default = "latest"
}

variable "COMFYUI_VERSION" {
  default = "latest"
}

# Global defaults for standard CUDA 12.6.3 images
variable "BASE_IMAGE" {
  default = "nvidia/cuda:12.6.3-cudnn-runtime-ubuntu24.04"
}

variable "CUDA_VERSION_FOR_COMFY" {
  default = "12.6"
}

variable "ENABLE_PYTORCH_UPGRADE" {
  default = "false"
}

variable "PYTORCH_INDEX_URL" {
  default = ""
}

group "default" {
  targets = ["base"]
}

target "base" {
  context = "."
  dockerfile = "Dockerfile"
  platforms = ["linux/amd64"]
  args = {
    BASE_IMAGE = "${BASE_IMAGE}"
    COMFYUI_VERSION = "${COMFYUI_VERSION}"
    CUDA_VERSION_FOR_COMFY = "${CUDA_VERSION_FOR_COMFY}"
    ENABLE_PYTORCH_UPGRADE = "${ENABLE_PYTORCH_UPGRADE}"
    PYTORCH_INDEX_URL = "${PYTORCH_INDEX_URL}"
  }
  tags = ["${DOCKERHUB_REPO}/${DOCKERHUB_IMG}:${RELEASE_VERSION}-base"]
}
