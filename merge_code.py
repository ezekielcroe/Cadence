import os

# --- CONFIGURATION ---
# Extensions to include
ALLOWED_EXTENSIONS = {".swift", ".h", ".m", ".c", ".cpp"}

# Directories to ignore
IGNORE_DIRS = {
    "Pods", 
    ".git", 
    "DerivedData", 
    "Assets.xcassets", 
    "Preview Content", 
    "fastlane",
    "build"
}

# Output file name
OUTPUT_FILE = "FullProjectSource.txt"

def merge_files():
    # Get current directory
    root_dir = os.getcwd()
    
    with open(OUTPUT_FILE, "w", encoding="utf-8") as outfile:
        # Walk through directory
        for dirpath, dirnames, filenames in os.walk(root_dir):
            # Remove ignored directories from traversal
            dirnames[:] = [d for d in dirnames if d not in IGNORE_DIRS]
            
            for filename in filenames:
                # Check extension
                ext = os.path.splitext(filename)[1]
                if ext in ALLOWED_EXTENSIONS:
                    file_path = os.path.join(dirpath, filename)
                    
                    # Create a relative path for cleaner reading
                    relative_path = os.path.relpath(file_path, root_dir)
                    
                    # Formatting the header for the output file
                    separator = "=" * 50
                    outfile.write(f"\n{separator}\n")
                    outfile.write(f"FILE: {relative_path}\n")
                    outfile.write(f"{separator}\n\n")
                    
                    try:
                        with open(file_path, "r", encoding="utf-8", errors="ignore") as infile:
                            outfile.write(infile.read())
                            outfile.write("\n")
                    except Exception as e:
                        print(f"Could not read {relative_path}: {e}")

    print(f"✅ Success! Source code combined into: {OUTPUT_FILE}")

if __name__ == "__main__":
    merge_files()