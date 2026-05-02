import os
from huggingface_hub import snapshot_download

model_id = "mlx-community/whisper-large-v3-turbo"
print(f"🚀 Testing download for {model_id}...")

try:
    path = snapshot_download(repo_id=model_id)
    print(f"✅ Download successful! Path: {path}")
except Exception as e:
    print(f"❌ Download failed: {e}")
