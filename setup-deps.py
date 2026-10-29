import hashlib
import os
import sys
import platform
import urllib.request
import zipfile
import shutil

ORGANIZATION = "moonlight-stream"
PREBUILT_REPO = "moonlight-qt-deps"
TAG = "v19"

# SHA-256 of each prebuilt archive. Release assets can be replaced after they're published, so a
# download that doesn't match isn't used. Add the hashes here when changing TAG.
SHA256 = {
    ("v19", "macos-universal.zip"): "39fab7c95f5d513a6eb3bb19c66f1ae66bbf41dfe4118f82fabe3b46cc502d17",
    ("v19", "steamlink.zip"): "b8f6f1d3efe936bcf0bea779da4e143394d166285821e0483b6f6f2fb4dd2de8",
}

def get_platform_config():
    system = platform.system()
    if system == "Darwin":
        return "mac", "macos-universal.zip"
    if system == "Linux":
        return "steamlink", "steamlink.zip"

    print(f"Error: Unsupported platform ({system})")
    sys.exit(1)

def download_and_extract():
    subfolder, asset_name = get_platform_config()
    
    target_dir = os.path.join(os.getcwd(), "libs", subfolder)
    url = f"https://github.com/{ORGANIZATION}/{PREBUILT_REPO}/releases/download/{TAG}/{asset_name}"
    expected = SHA256.get((TAG, asset_name))
    if expected is None:
        print(f"Error: no SHA-256 for {asset_name} at {TAG}; add it to SHA256 in setup-deps.py")
        sys.exit(1)

    # [fork] Already deployed from this archive: a local build doesn't download it again
    stamp = os.path.join(target_dir, ".deployed")
    if os.path.exists(stamp):
        with open(stamp) as f:
            if f.read().strip() == f"{TAG} {asset_name} {expected}":
                print(f"{asset_name} at {TAG} is already deployed")
                return

    if os.path.exists(target_dir):
        print("Cleaning target directory...")
        shutil.rmtree(target_dir)

    os.makedirs(target_dir, exist_ok=True)

    archive_path = os.path.join(target_dir, asset_name)

    print(f"Downloading {asset_name}...")
    try:
        urllib.request.urlretrieve(url, archive_path)
    except Exception as e:
        print(f"Download failed: {e}")
        sys.exit(1)

    digest = hashlib.sha256()
    with open(archive_path, "rb") as archive:
        for chunk in iter(lambda: archive.read(1 << 20), b""):
            digest.update(chunk)
    if digest.hexdigest() != expected:
        print(f"Error: {asset_name} has SHA-256 {digest.hexdigest()}, expected {expected}")
        os.remove(archive_path)
        sys.exit(1)

    print(f"Extracting {asset_name}...")
    with zipfile.ZipFile(archive_path, 'r') as zip_ref:
        zip_ref.extractall(target_dir)

    os.remove(archive_path)
    with open(stamp, "w") as f:
        f.write(f"{TAG} {asset_name} {expected}\n")
    print(f"Dependencies successfully deployed")

if __name__ == "__main__":
    download_and_extract()