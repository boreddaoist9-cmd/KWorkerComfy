# Build argument for base image selection
ARG BASE_IMAGE=nvidia/cuda:12.6.3-cudnn-runtime-ubuntu24.04

# Stage 1: Base image with common dependencies
FROM ${BASE_IMAGE} AS base

# Build arguments for this stage with sensible defaults for standalone builds
ARG COMFYUI_VERSION=latest
ARG CUDA_VERSION_FOR_COMFY
ARG ENABLE_PYTORCH_UPGRADE=false
ARG PYTORCH_INDEX_URL

# Prevents prompts from packages asking for user input during installation
ENV DEBIAN_FRONTEND=noninteractive
# Prefer binary wheels over source distributions for faster pip installations
ENV PIP_PREFER_BINARY=1
# Ensures output from python is printed immediately to the terminal without buffering
ENV PYTHONUNBUFFERED=1
# Speed up some cmake builds
ENV CMAKE_BUILD_PARALLEL_LEVEL=8

# Install Python, git and other necessary tools
RUN apt-get update && apt-get install -y \
    python3.12 \
    python3.12-venv \
    git \
    wget \
    libgl1 \
    libglib2.0-0 \
    libsm6 \
    libxext6 \
    libxrender1 \
    ffmpeg \
    && ln -sf /usr/bin/python3.12 /usr/bin/python \
    && ln -sf /usr/bin/pip3 /usr/bin/pip

# Clean up to reduce image size
RUN apt-get autoremove -y && apt-get clean -y && rm -rf /var/lib/apt/lists/*

# Install python3.12-dev for InsightFace compilation and build dependencies for custom nodes
RUN apt-get update && apt-get install -y \
    python3.12-dev \
    build-essential \
    pkg-config \
    libcairo2-dev \
    libgirepository1.0-dev \
    && apt-get autoremove -y && apt-get clean -y && rm -rf /var/lib/apt/lists/*

# Install uv (latest) using official installer and create isolated venv
RUN wget -qO- https://astral.sh/uv/install.sh | sh \
    && ln -s /root/.local/bin/uv /usr/local/bin/uv \
    && ln -s /root/.local/bin/uvx /usr/local/bin/uvx \
    && uv venv /opt/venv

# Use the virtual environment for all subsequent commands
ENV PATH="/opt/venv/bin:${PATH}"

# Install comfy-cli + dependencies needed by it to install ComfyUI
RUN uv pip install comfy-cli pip setuptools wheel

# Install ComfyUI
RUN if [ -n "${CUDA_VERSION_FOR_COMFY}" ]; then \
      /usr/bin/yes | comfy --workspace /comfyui install --version "${COMFYUI_VERSION}" --cuda-version "${CUDA_VERSION_FOR_COMFY}" --nvidia; \
    else \
      /usr/bin/yes | comfy --workspace /comfyui install --version "${COMFYUI_VERSION}" --nvidia; \
    fi

# Upgrade PyTorch if needed (for newer CUDA versions)
RUN if [ "$ENABLE_PYTORCH_UPGRADE" = "true" ]; then \
      uv pip install --force-reinstall torch torchvision torchaudio --index-url ${PYTORCH_INDEX_URL}; \
    fi

# Change working directory to ComfyUI
WORKDIR /comfyui

# Support for the network volume
ADD src/extra_model_paths.yaml ./

# Install git custom nodes from snapshot
RUN cd custom_nodes && \
    git clone https://github.com/WASasquatch/was-node-suite-comfyui && \
    cd was-node-suite-comfyui && if [ -f requirements.txt ]; then uv pip install -r requirements.txt || exit 1; fi && cd .. && \
    git clone https://github.com/kijai/ComfyUI-KJNodes && \
    cd ComfyUI-KJNodes && if [ -f requirements.txt ]; then uv pip install -r requirements.txt || exit 1; fi && cd .. && \
    git clone https://github.com/cubiq/ComfyUI_essentials && \
    cd ComfyUI_essentials && if [ -f requirements.txt ]; then uv pip install -r requirements.txt || exit 1; fi && cd .. && \
    git clone https://github.com/1038lab/ComfyUI-RMBG && \
    cd ComfyUI-RMBG && if [ -f requirements.txt ]; then uv pip install -r requirements.txt || exit 1; fi && cd .. && \
    git clone https://github.com/rgthree/rgthree-comfy && \
    cd rgthree-comfy && if [ -f requirements.txt ]; then uv pip install -r requirements.txt || exit 1; fi && cd .. && \
    git clone https://github.com/djbielejeski/a-person-mask-generator && \
    cd a-person-mask-generator && if [ -f requirements.txt ]; then uv pip install -r requirements.txt || exit 1; fi && cd .. && \
    git clone https://github.com/tsogzark/ComfyUI-load-image-from-url && \
    cd ComfyUI-load-image-from-url && if [ -f requirements.txt ]; then uv pip install -r requirements.txt || exit 1; fi && cd .. && \
    git clone https://github.com/sipie800/ComfyUI-PuLID-Flux-Enhanced && \
    cd ComfyUI-PuLID-Flux-Enhanced && if [ -f requirements.txt ]; then uv pip install -r requirements.txt || exit 1; fi && cd .. && \
    git clone https://github.com/Comfy-Org/ComfyUI-Manager && \
    cd ComfyUI-Manager && if [ -f requirements.txt ]; then uv pip install -r requirements.txt || exit 1; fi && cd ../..

# Download InsightFace antelopev2 models to ComfyUI models folder
RUN mkdir -p models/insightface/models/antelopev2 && \
    cd models/insightface/models/antelopev2 && \
    wget -q https://huggingface.co/DIAMONIK7777/antelopev2/resolve/main/1k3d68.onnx && \
    wget -q https://huggingface.co/DIAMONIK7777/antelopev2/resolve/main/2d106det.onnx && \
    wget -q https://huggingface.co/DIAMONIK7777/antelopev2/resolve/main/genderage.onnx && \
    wget -q https://huggingface.co/DIAMONIK7777/antelopev2/resolve/main/glintr100.onnx && \
    wget -q https://huggingface.co/DIAMONIK7777/antelopev2/resolve/main/scrfd_10g_bnkps.onnx

# Download PuLID Flux model
RUN mkdir -p models/pulid && \
    cd models/pulid && \
    wget -q https://huggingface.co/guozinan/PuLID/resolve/main/pulid_flux_v0.9.1.safetensors

# Go back to the root
WORKDIR /

# Install Python runtime dependencies for the handler
RUN uv pip install runpod requests websocket-client

# Install InsightFace
RUN python -m pip install insightface

# Add application code and scripts
ADD src/start.sh handler.py test_input.json ./
RUN chmod +x /start.sh

# Add script to install custom nodes
COPY scripts/comfy-node-install.sh /usr/local/bin/comfy-node-install
RUN chmod +x /usr/local/bin/comfy-node-install

# Prevent pip from asking for confirmation during uninstall steps in custom nodes
ENV PIP_NO_INPUT=1

# Copy helper script to switch Manager network mode at container start
COPY scripts/comfy-manager-set-mode.sh /usr/local/bin/comfy-manager-set-mode
RUN chmod +x /usr/local/bin/comfy-manager-set-mode

# Set the default command to run when starting the container
CMD ["/start.sh"]
