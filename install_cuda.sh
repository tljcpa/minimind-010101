#!/bin/bash
set -e
set -o pipefail

# ---------------- CONFIG ----------------
TARGET_CUDA_VERSION="12-4"
PYTORCH_CUDA_TAG="cu124"

# ---------------- STEP 0: Detect Ubuntu version ----------------
if command -v lsb_release >/dev/null 2>&1; then
    OS_VERSION=$(lsb_release -rs | tr -d '.')
else
    . /etc/os-release
    OS_VERSION=$(echo "$VERSION_ID" | tr -d '.')
fi

if [ -z "$OS_VERSION" ]; then
    echo "Error: Could not detect Ubuntu version."
    exit 1
fi
echo "Detected OS Version: Ubuntu $OS_VERSION"

# ---------------- STEP 1: Update system ----------------
echo "================ STEP 1: Update system ================"
sudo apt update && sudo apt upgrade -y

# ---------------- STEP 2: Install basic tools ----------------
echo "================ STEP 2: Install basic tools ================"
install_if_missing() {
    local CMD="$1"
    local PKG="$2"
    if ! command -v "$CMD" &> /dev/null; then
        echo "Installing $PKG..."
        sudo apt install -y "$PKG"
    else
        echo "$CMD already installed"
    fi
}

install_if_missing python3 python3
install_if_missing pip3 python3-pip
install_if_missing git git
install_if_missing wget wget
install_if_missing curl curl
install_if_missing lspci pciutils
dpkg -s software-properties-common &> /dev/null || sudo apt install -y software-properties-common
dpkg -s build-essential &> /dev/null || sudo apt install -y build-essential

# ---------------- STEP 3: Detect NVIDIA GPU ----------------
echo "================ STEP 3: Detect NVIDIA GPU ================"
GPU_FLAG=0
if lspci | grep -i nvidia &> /dev/null; then
    GPU_FLAG=1
    echo "NVIDIA GPU detected."
else
    echo "No NVIDIA GPU detected. Using CPU."
fi

# ---------------- STEP 4: Install NVIDIA Driver & CUDA ----------------
echo "================ STEP 4: Install NVIDIA Driver & CUDA ================"
if [ "$GPU_FLAG" -eq 1 ]; then
    if ! command -v nvidia-smi &> /dev/null; then
        echo "Installing NVIDIA repository and drivers..."
        KEYRING_URL="https://developer.download.nvidia.com/compute/cuda/repos/ubuntu${OS_VERSION}/x86_64/cuda-keyring_1.1-1_all.deb"
        if ! wget -q "$KEYRING_URL" -O cuda-keyring.deb; then
            echo "Error: Failed to download cuda keyring from $KEYRING_URL"
            exit 1
        fi
        sudo dpkg -i cuda-keyring.deb
        rm -f cuda-keyring.deb
        sudo apt update

        echo "Installing CUDA Toolkit $TARGET_CUDA_VERSION and drivers..."
        sudo apt install -y "cuda-toolkit-${TARGET_CUDA_VERSION}" cuda-drivers

        # Configure environment variables
        echo 'export PATH=/usr/local/cuda/bin:$PATH' | sudo tee /etc/profile.d/cuda.sh
        echo 'export LD_LIBRARY_PATH=/usr/local/cuda/lib64:$LD_LIBRARY_PATH' | sudo tee -a /etc/profile.d/cuda.sh

        # Temporary session export
        export PATH=/usr/local/cuda/bin:$PATH
        export LD_LIBRARY_PATH=/usr/local/cuda/lib64:$LD_LIBRARY_PATH

        echo "NOTE: You must reboot after this script finishes to load drivers."
    else
        echo "NVIDIA driver/CUDA already installed."
    fi

    # Install cuDNN
    echo "Installing cuDNN..."
    if sudo apt show libcudnn9-cuda-12 &> /dev/null; then
        sudo apt install -y libcudnn9-cuda-12 libcudnn9-dev-cuda-12 || true
    elif sudo apt show libcudnn8-dev &> /dev/null; then
        sudo apt install -y libcudnn8-dev || true
    else
        echo "Warning: Could not find cuDNN package. Manual installation may be required."
    fi
fi

# ---------------- STEP 5: Upgrade pip ----------------
echo "================ STEP 5: Upgrade pip ================="
pip3 install --upgrade pip || echo "Warning: Pip upgrade failed. Ignore if using Ubuntu 24.04+."

# ---------------- STEP 6: Install PyTorch ----------------
echo "================ STEP 6: Install PyTorch ================="
if [ "$GPU_FLAG" -eq 1 ]; then
    echo "Installing PyTorch (matching CUDA $TARGET_CUDA_VERSION)..."
    pip3 install --no-cache-dir torch torchvision torchaudio --extra-index-url https://download.pytorch.org/whl/$PYTORCH_CUDA_TAG
else
    echo "Installing CPU version of PyTorch..."
    pip3 install torch torchvision torchaudio --extra-index-url https://download.pytorch.org/whl/cpu
fi

# ---------------- STEP 7: Install Python dependencies ----------------
echo "================ STEP 7: Install Python dependencies ================"
if [ -f requirements.txt ]; then
    pip3 install -r requirements.txt -i https://mirrors.aliyun.com/pypi/simple || echo "Warning: requirements.txt install failed"
fi

# ---------------- STEP 8: Install NLTK resources ----------------
echo "================ STEP 8: NLTK resources ================="
pip3 install nltk || echo "Warning: nltk install failed"
python3 -m nltk.downloader punkt stopwords || echo "Warning: nltk downloader failed"

# ---------------- STEP 9: Final Report ----------------
echo "================ STEP 9: Final Report ================="
echo "Setup complete."
if [ "$GPU_FLAG" -eq 1 ]; then
    echo "IMPORTANT: If you installed drivers, reboot now."
    echo "Run 'nvidia-smi' after reboot to verify installation."
fi
echo "CPU/GPU flag: $GPU_FLAG"
echo "CUDA version target: $TARGET_CUDA_VERSION"
echo "PyTorch tag: $PYTORCH_CUDA_TAG"