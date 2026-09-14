# upload_to_sharepoint.py
"""
SharePoint Upload Script for IM Workflow
Uploads cleaned IM repository and associated files to SharePoint after pipeline completion
"""

import requests
from pathlib import Path
import sys
import os
from datetime import datetime

# ============================================================
# CONFIGURATION
# ============================================================

# Base directory for IM workflow
# Set once via `setx IM_WORKFLOW_HOME "D:/new/path"` (Windows) if this
# project ever moves off this laptop/drive -- every script in the pipeline
# reads the same variable, so nothing else needs editing.
BASE_DIR = os.environ.get("IM_WORKFLOW_HOME", r"C:/Users/TOURE/Documents/im_workflow")
FINAL_DIR = os.path.join(BASE_DIR, "data/final")

# Authentication credentials — loaded from environment variables, never
# hardcoded here (this file is tracked in git). Set them once via a local,
# git-ignored config/secrets.env file (copy config/secrets.env.example),
# or via `setx` / `export` in your shell.
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _env_loader import load_secrets_env
load_secrets_env(BASE_DIR)

TENANT_ID = os.environ.get("SHAREPOINT_TENANT_ID", "")
CLIENT_ID = os.environ.get("SHAREPOINT_CLIENT_ID", "")
CLIENT_SECRET = os.environ.get("SHAREPOINT_CLIENT_SECRET", "")

if not all([TENANT_ID, CLIENT_ID, CLIENT_SECRET]):
    raise RuntimeError(
        "Missing SharePoint credentials. Set SHAREPOINT_TENANT_ID, SHAREPOINT_CLIENT_ID "
        "and SHAREPOINT_CLIENT_SECRET as environment variables, or fill in "
        "config/secrets.env (copy config/secrets.env.example to get started)."
    )

# SharePoint configuration
HOSTNAME = "worldhealthorg.sharepoint.com"
SITE_PATH = "/sites/AF-pep/GISWORKSPACE"
LIBRARY_NAME = "Documents"

# Target folder path (relative to Documents library)
# Format: use forward slashes, no leading slash
TARGET_FOLDER = "7. SIA_Data/Data Repository"  # <- UPDATE THIS AS NEEDED

# File mappings: (local_filename, remote_filename, required)
FILE_MAPPINGS = [
    {
        "local": "Regional_IM_repository_cleaned.csv",
        "remote": "AFRO_Inside_HH_M.csv",
        "required": True,
        "description": "Main cleaned IM repository"
    },
    {
        "local": "Regional_IM_repository_QC.csv",
        "remote": "AFRO_Inside_HH_M_QC.csv",
        "required": True,
        "description": "QC repository for review"
    },
    {
        "local": "Regional_IM_repository_METADATA.xlsx",
        "remote": "AFRO_Inside_HH_M_METADATA.xlsx",
        "required": True,
        "description": "Metadata and variable dictionary"
    },
    {
        "local": "export_manifest.txt",
        "remote": "AFRO_Inside_HH_M_manifest.txt",
        "required": False,
        "description": "Export manifest"
    },
    {
        "local": "IM_processing_summary.csv",
        "remote": "AFRO_Inside_HH_M_processing_summary.csv",
        "required": False,
        "description": "Processing summary statistics"
    },
    {
        "local": "IM_geonames_cleaning_summary.csv",
        "remote": "AFRO_Inside_HH_M_geonames_summary.csv",
        "required": False,
        "description": "Geonames cleaning summary"
    }
]

# ============================================================
# HELPER FUNCTIONS FOR WINDOWS CONSOLE
# ============================================================

def safe_print(message, use_unicode=False):
    """Print safely without Unicode errors on Windows"""
    try:
        print(message)
    except UnicodeEncodeError:
        ascii_message = (message.replace('✓', '[OK]')
                               .replace('✗', '[FAIL]')
                               .replace('○', '[SKIP]')
                               .replace('✅', '[SUCCESS]')
                               .replace('⚠️', '[WARNING]'))
        print(ascii_message)

# ============================================================
# FUNCTIONS
# ============================================================

def get_token():
    """Get Microsoft Graph access token"""
    url = f"https://login.microsoftonline.com/{TENANT_ID}/oauth2/v2.0/token"
    data = {
        "client_id": CLIENT_ID,
        "client_secret": CLIENT_SECRET,
        "scope": "https://graph.microsoft.com/.default",
        "grant_type": "client_credentials"
    }
    try:
        r = requests.post(url, data=data, timeout=30)
        r.raise_for_status()
        return r.json()["access_token"]
    except requests.exceptions.RequestException as e:
        print(f"ERROR: Failed to get token: {e}")
        raise

def request_with_auth(method, url, token, **kwargs):
    """Make authenticated request"""
    headers = kwargs.pop("headers", {})
    headers["Authorization"] = f"Bearer {token}"
    
    try:
        r = requests.request(method, url, headers=headers, timeout=120, **kwargs)
        print(f"  {method} {url.split('?')[0][-60:]} -> {r.status_code}")
        
        if not r.ok:
            print(f"  Error response: {r.text[:300]}")
        r.raise_for_status()
        return r.json() if r.text else None
    except requests.exceptions.RequestException as e:
        print(f"  Request failed: {e}")
        raise

def get_site_and_drive(token):
    """Get SharePoint site and document library"""
    
    # Get site
    site_url = f"https://graph.microsoft.com/v1.0/sites/{HOSTNAME}:{SITE_PATH}"
    site = request_with_auth("GET", site_url, token)
    site_id = site["id"]
    print(f"[OK] Site: {site.get('displayName', SITE_PATH)}")
    
    # Get drives (document libraries)
    drives_url = f"https://graph.microsoft.com/v1.0/sites/{site_id}/drives"
    drives = request_with_auth("GET", drives_url, token)
    
    # Find the target library
    drive = None
    for d in drives["value"]:
        if d["name"].lower() == LIBRARY_NAME.lower():
            drive = d
            break
    
    if not drive:
        print(f"  Available libraries: {[d['name'] for d in drives['value']]}")
        raise Exception(f"Library '{LIBRARY_NAME}' not found")
    
    drive_id = drive["id"]
    print(f"[OK] Library: {drive['name']}")
    
    return site_id, drive_id

def create_folder_if_not_exists(token, drive_id, folder_path):
    """Create folder hierarchy if it doesn't exist"""
    print(f"  Checking/Creating folder: {folder_path}")
    
    # Split folder path into parts
    folders = folder_path.split('/')
    current_path = ""
    
    for folder in folders:
        if not folder:
            continue
        
        if current_path:
            current_path = f"{current_path}/{folder}"
        else:
            current_path = folder
        
        # Check if folder exists
        check_url = f"https://graph.microsoft.com/v1.0/drives/{drive_id}/root:/{current_path}"
        try:
            result = request_with_auth("GET", check_url, token)
            print(f"    Folder exists: {folder}")
        except:
            # Folder doesn't exist, create it
            print(f"    Creating folder: {folder}")
            parent_path = "/".join(current_path.split('/')[:-1]) if '/' in current_path else ""
            
            if parent_path:
                create_url = f"https://graph.microsoft.com/v1.0/drives/{drive_id}/root:/{parent_path}:/children"
            else:
                create_url = f"https://graph.microsoft.com/v1.0/drives/{drive_id}/root/children"
            
            folder_data = {
                "name": folder,
                "folder": {},
                "@microsoft.graph.conflictBehavior": "rename"
            }
            
            try:
                # Need to use a different approach for folder creation
                # Use the items endpoint instead
                if parent_path:
                    # Get parent folder ID first
                    parent_url = f"https://graph.microsoft.com/v1.0/drives/{drive_id}/root:/{parent_path}"
                    parent = request_with_auth("GET", parent_url, token)
                    parent_id = parent["id"]
                    create_url = f"https://graph.microsoft.com/v1.0/drives/{drive_id}/items/{parent_id}/children"
                else:
                    create_url = f"https://graph.microsoft.com/v1.0/drives/{drive_id}/root/children"
                
                result = request_with_auth("POST", create_url, token, json=folder_data)
                print(f"    Created folder: {folder}")
            except Exception as e:
                print(f"    Warning: Could not create folder {folder}: {e}")
    
    return current_path

def upload_file(token, drive_id, local_path, remote_filename, folder_path=None):
    """Upload a single file to SharePoint (overwrites if exists)"""
    
    # Check file exists
    if not Path(local_path).exists():
        raise FileNotFoundError(f"File not found: {local_path}")
    
    file_size = Path(local_path).stat().st_size
    file_size_mb = file_size / 1024 / 1024
    
    # Build the remote path
    if folder_path:
        # Ensure folder path doesn't have leading/trailing slashes
        folder_path = folder_path.strip('/')
        remote_path = f"{folder_path}/{remote_filename}"
    else:
        remote_path = remote_filename
    
    print(f"  Uploading: {Path(local_path).name} ({file_size_mb:.2f} MB)")
    print(f"    -> {remote_path}")
    
    # Read file content
    with open(local_path, "rb") as f:
        file_content = f.read()
    
    # Upload with PUT (this REPLACES the existing file)
    upload_url = f"https://graph.microsoft.com/v1.0/drives/{drive_id}/root:/{remote_path}:/content"
    
    result = request_with_auth(
        "PUT",
        upload_url,
        token,
        headers={"Content-Type": "application/octet-stream"},
        data=file_content
    )
    
    print(f"  [OK] Uploaded: {result['name']} ({result.get('size', 0):,} bytes)")
    return result

def upload_to_sharepoint():
    """Upload files to SharePoint"""
    
    print("=" * 70)
    print("SHAREPOINT UPLOAD - IM WORKFLOW")
    print("=" * 70)
    print(f"Source directory: {FINAL_DIR}")
    print(f"Target site: {SITE_PATH}")
    print(f"Target library: {LIBRARY_NAME}")
    print(f"Target folder: {TARGET_FOLDER if TARGET_FOLDER else '(root)'}")
    print("=" * 70)
    
    # Check if final directory exists
    if not os.path.exists(FINAL_DIR):
        print(f"ERROR: Directory not found: {FINAL_DIR}")
        return False
    
    # Get authentication token
    print("\n[1/5] Authenticating...")
    token = get_token()
    print("[OK] Token acquired")
    
    # Get site and drive
    print("\n[2/5] Connecting to SharePoint...")
    site_id, drive_id = get_site_and_drive(token)
    
    # Create target folder if it doesn't exist
    print("\n[3/5] Ensuring target folder exists...")
    if TARGET_FOLDER:
        folder_path = create_folder_if_not_exists(token, drive_id, TARGET_FOLDER)
    else:
        folder_path = None
    
    # Upload files
    print("\n[4/5] Uploading files...")
    print("-" * 50)
    
    uploaded_files = []
    failed_files = []
    
    for file_info in FILE_MAPPINGS:
        local_path = os.path.join(FINAL_DIR, file_info["local"])
        
        # Skip if not required and file doesn't exist
        if not os.path.exists(local_path):
            if file_info["required"]:
                print(f"  [FAIL] REQUIRED file missing: {file_info['local']}")
                failed_files.append(file_info)
            else:
                print(f"  [SKIP] Not found: {file_info['local']}")
            continue
        
        # Upload the file
        try:
            result = upload_file(token, drive_id, local_path, file_info["remote"], folder_path)
            uploaded_files.append({
                "local": file_info["local"],
                "remote": file_info["remote"],
                "size": result.get('size', 0),
                "url": result.get('webUrl')
            })
        except Exception as e:
            print(f"  [FAIL] Upload failed: {file_info['local']} - {e}")
            failed_files.append(file_info)
    
    # Summary
    print("\n[5/5] Upload Summary")
    print("=" * 70)
    
    if uploaded_files:
        print("\n[SUCCESS] Successfully uploaded:")
        for f in uploaded_files:
            size_mb = f['size'] / 1024 / 1024
            print(f"  - {f['remote']} ({size_mb:.2f} MB)")
            if f.get('url'):
                print(f"    URL: {f['url']}")
    
    if failed_files:
        print("\n[FAIL] Failed/Not uploaded:")
        for f in failed_files:
            print(f"  - {f['remote']} ({f['description']})")
    
    # Full SharePoint URL for manual access
    if uploaded_files:
        print("\n" + "=" * 70)
        print("ACCESS YOUR FILES:")
        sharepoint_url = f"https://{HOSTNAME}{SITE_PATH}/{LIBRARY_NAME}"
        if TARGET_FOLDER:
            sharepoint_url += f"/{TARGET_FOLDER}"
        print(f"  {sharepoint_url}")
        print("=" * 70)
    
    return len(failed_files) == 0

def test_connection():
    """Test if we can connect to the SharePoint site"""
    print("Testing SharePoint connection...")
    print("-" * 50)
    
    try:
        token = get_token()
        print("[OK] Token acquired")
        
        # Test site access
        test_url = f"https://graph.microsoft.com/v1.0/sites/{HOSTNAME}:{SITE_PATH}"
        response = requests.get(test_url, headers={"Authorization": f"Bearer {token}"})
        
        if response.status_code == 200:
            site_data = response.json()
            print(f"[OK] Site accessible: {site_data.get('displayName')}")
            print(f"[OK] Site ID: {site_data.get('id')}")
            return True
        else:
            print(f"[FAIL] Cannot access site: {response.status_code}")
            print(f"Response: {response.text[:300]}")
            return False
            
    except Exception as e:
        print(f"[FAIL] Connection test failed: {e}")
        return False

def check_local_files():
    """Check which files exist locally before upload"""
    print("\nLocal files check:")
    print("-" * 50)
    
    existing = []
    missing = []
    
    for file_info in FILE_MAPPINGS:
        local_path = os.path.join(FINAL_DIR, file_info["local"])
        if os.path.exists(local_path):
            size_mb = Path(local_path).stat().st_size / 1024 / 1024
            print(f"  [OK] {file_info['local']} ({size_mb:.2f} MB)")
            existing.append(file_info)
        else:
            print(f"  [MISSING] {file_info['local']}")
            missing.append(file_info)
    
    return existing, missing

# ============================================================
# MAIN EXECUTION
# ============================================================

if __name__ == "__main__":
    import argparse
    
    # Set UTF-8 for stdout on Windows
    if sys.platform == "win32":
        import io
        sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8', errors='replace')
    
    parser = argparse.ArgumentParser(description="Upload IM workflow outputs to SharePoint")
    parser.add_argument("--test", action="store_true", help="Test connection only")
    parser.add_argument("--check", action="store_true", help="Check local files only")
    parser.add_argument("--file", type=str, help="Upload only specific file (local name)")
    parser.add_argument("--folder", type=str, help="Target folder path (overrides TARGET_FOLDER)")
    parser.add_argument("--all", action="store_true", default=True, help="Upload all files (default)")
    
    args = parser.parse_args()
    
    # Override folder if provided
    if args.folder:
        TARGET_FOLDER = args.folder
    
    print("\n" + "=" * 70)
    print("IM WORKFLOW - SHAREPOINT UPLOAD UTILITY")
    print("=" * 70)
    print(f"Time: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    
    if args.test:
        print("\nTEST MODE\n")
        if not test_connection():
            sys.exit(1)

    elif args.check:
        existing, missing = check_local_files()
        required_missing = [f for f in missing if f["required"]]
        if required_missing:
            print(f"\n[FAIL] {len(required_missing)} required file(s) missing.")
            sys.exit(1)

    elif args.file:
        # Upload single file (implementation kept but simplified)
        print(f"\nUse --all to upload files to {TARGET_FOLDER}")
        print("Single file upload not implemented in this version.")
        
    else:
        # Upload all files
        print("\nFULL UPLOAD MODE\n")
        
        # First check local files
        existing, missing = check_local_files()
        
        if not existing:
            print("\nERROR: No files found to upload!")
            print("Please run the IM workflow first to generate output files.")
            sys.exit(1)
        
        # Upload
        success = upload_to_sharepoint()
        
        if success:
            print("\n[SUCCESS] ALL FILES UPLOADED SUCCESSFULLY!")
        else:
            print("\n[WARNING] SOME UPLOADS FAILED - Check errors above")
            sys.exit(1)