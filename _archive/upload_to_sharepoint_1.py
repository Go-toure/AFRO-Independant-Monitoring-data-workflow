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

# Authentication credentials -- loaded from environment variables, never
# hardcoded here (this file is tracked in git). A real secret used to sit
# here directly; it was removed after GitHub's push protection caught it,
# and the Azure AD app secret should be rotated in Azure regardless. Set
# these via a local, git-ignored config/secrets.env file (copy
# config/secrets.env.example), or via `setx` / `export` in your shell.
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _env_loader import load_secrets_env
load_secrets_env(os.path.dirname(os.path.abspath(__file__)))

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
LIBRARY_NAME = "Documents"  # Could be "Documents" or "Shared Documents"

# Base directory for IM workflow
BASE_DIR = r"C:/Users/TOURE/Documents/im_workflow"
FINAL_DIR = os.path.join(BASE_DIR, "data/final")

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
        # Replace Unicode characters with ASCII equivalents
        ascii_message = (message.replace('✓', '[OK]')
                               .replace('✗', '[FAIL]')
                               .replace('○', '[SKIP]')
                               .replace('✅', '[SUCCESS]')
                               .replace('⚠️', '[WARNING]')
                               .replace('📁', '[FOLDER]')
                               .replace('🔍', '[SEARCH]')
                               .replace('📊', '[DATA]')
                               .replace('📋', '[FILE]')
                               .replace('📘', '[DOC]')
                               .replace('🎉', '[DONE]')
                               .replace('🏆', '[WIN]')
                               .replace('⭐', '[STAR]'))
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
        if hasattr(e, 'response') and e.response:
            print(f"Response: {e.response.text[:500]}")
        raise

def request_with_auth(method, url, token, **kwargs):
    """Make authenticated request"""
    headers = kwargs.pop("headers", {})
    headers["Authorization"] = f"Bearer {token}"
    
    try:
        r = requests.request(method, url, headers=headers, timeout=120, **kwargs)
        print(f"  {method} {url.split('?')[0][-50:]} -> {r.status_code}")
        
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

def upload_file(token, drive_id, local_path, remote_filename):
    """Upload a single file to SharePoint (overwrites if exists)"""
    
    # Check file exists
    if not Path(local_path).exists():
        raise FileNotFoundError(f"File not found: {local_path}")
    
    file_size = Path(local_path).stat().st_size
    file_size_mb = file_size / 1024 / 1024
    
    print(f"  Uploading: {Path(local_path).name} ({file_size_mb:.2f} MB) -> {remote_filename}")
    
    # Read file content
    with open(local_path, "rb") as f:
        file_content = f.read()
    
    # Upload with PUT (this REPLACES the existing file)
    upload_url = f"https://graph.microsoft.com/v1.0/drives/{drive_id}/root:/{remote_filename}:/content"
    
    result = request_with_auth(
        "PUT",
        upload_url,
        token,
        headers={"Content-Type": "application/octet-stream"},
        data=file_content
    )
    
    print(f"  [OK] Uploaded: {result['name']} ({result.get('size', 0):,} bytes)")
    return result

def upload_to_sharepoint(upload_all=True):
    """Upload files to SharePoint"""
    
    print("=" * 70)
    print("SHAREPOINT UPLOAD - IM WORKFLOW")
    print("=" * 70)
    print(f"Source directory: {FINAL_DIR}")
    print(f"Target site: {SITE_PATH}")
    print(f"Target library: {LIBRARY_NAME}")
    print("=" * 70)
    
    # Check if final directory exists
    if not os.path.exists(FINAL_DIR):
        print(f"ERROR: Directory not found: {FINAL_DIR}")
        return False
    
    # Get authentication token
    print("\n[1/4] Authenticating...")
    token = get_token()
    print("[OK] Token acquired")
    
    # Get site and drive
    print("\n[2/4] Connecting to SharePoint...")
    site_id, drive_id = get_site_and_drive(token)
    
    # Upload files
    print("\n[3/4] Uploading files...")
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
            result = upload_file(token, drive_id, local_path, file_info["remote"])
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
    print("\n[4/4] Upload Summary")
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
    
    print("\n" + "=" * 70)
    
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
    parser.add_argument("--all", action="store_true", default=True, help="Upload all files (default)")
    
    args = parser.parse_args()
    
    print("\n" + "=" * 70)
    print("IM WORKFLOW - SHAREPOINT UPLOAD UTILITY")
    print("=" * 70)
    print(f"Time: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    
    if args.test:
        # Test connection only
        print("\nTEST MODE\n")
        test_connection()
        
    elif args.check:
        # Check local files only
        check_local_files()
        
    elif args.file:
        # Upload single file (override mapping)
        local_file = args.file
        local_path = os.path.join(FINAL_DIR, local_file)
        
        if not os.path.exists(local_path):
            print(f"\nERROR: File not found: {local_path}")
            sys.exit(1)
        
        # Find remote name from mapping or use same name
        remote_name = local_file
        for mapping in FILE_MAPPINGS:
            if mapping["local"] == local_file:
                remote_name = mapping["remote"]
                break
        
        print(f"\nUploading single file:")
        print(f"  Local: {local_file}")
        print(f"  Remote: {remote_name}")
        
        try:
            token = get_token()
            site_id, drive_id = get_site_and_drive(token)
            result = upload_file(token, drive_id, local_path, remote_name)
            print(f"\n[SUCCESS] Upload successful!")
        except Exception as e:
            print(f"\n[FAIL] Upload failed: {e}")
            sys.exit(1)
            
    else:
        # Upload all files
        print("\nFULL UPLOAD MODE\n")
        
        # First check local files
        existing, missing = check_local_files()
        
        if not existing:
            print("\nERROR: No files found to upload!")
            print("Please run the IM workflow first to generate output files.")
            sys.exit(1)
        
        # Ask for confirmation if missing required files
        required_missing = [f for f in missing if f["required"]]
        if required_missing:
            print(f"\nWARNING: Required files are missing: {[f['local'] for f in required_missing]}")
            # Auto-continue in non-interactive mode
            if sys.stdin.isatty():
                response = input("Continue anyway? (y/n): ")
                if response.lower() != 'y':
                    print("Upload cancelled.")
                    sys.exit(0)
            else:
                print("Non-interactive mode: continuing with available files...")
        
        # Upload
        success = upload_to_sharepoint()
        
        if success:
            print("\n[SUCCESS] ALL FILES UPLOADED SUCCESSFULLY!")
            print("\nSharePoint files updated:")
            print(f"  - AFRO_Inside_HH_M.csv (main data)")
            print(f"  - AFRO_Inside_HH_M_QC.csv (quality control)")
            print(f"  - AFRO_Inside_HH_M_METADATA.xlsx (documentation)")
            print(f"  - AFRO_Inside_HH_M_manifest.txt (export manifest)")
            print(f"  - AFRO_Inside_HH_M_processing_summary.csv")
            print(f"  - AFRO_Inside_HH_M_geonames_summary.csv")
        else:
            print("\n[WARNING] SOME UPLOADS FAILED - Check errors above")
            sys.exit(1)