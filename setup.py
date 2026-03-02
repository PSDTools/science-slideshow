#!/usr/bin/env python3
import subprocess
import sys
import os
import time

def main():
    print("==================================================")
    print(" Slideshow Kiosk Setup")
    print("==================================================")
    
    # Ensure we run from the repository directory
    script_dir = os.path.dirname(os.path.abspath(__file__))
    os.chdir(script_dir)
    
    # Ensure scripts are executable
    subprocess.run(["chmod", "+x", "tune-pi.sh", "deploy.sh"], check=False)

    print("\n>>> 1/2: Running System Tuning (tune-pi.sh)")
    print("    This step configures GPU memory, swap, and CPU performance.")
    try:
        # We run tune-pi.sh with sudo. 
        subprocess.run(["sudo", "./tune-pi.sh"], check=True)
    except subprocess.CalledProcessError as e:
        print(f"\n[ERROR] tune-pi.sh failed with exit code {e.returncode}")
        sys.exit(1)
        
    print("\n>>> 2/2: Deploying App and Kiosk Autostart (deploy.sh)")
    try:
        # deploy.sh manages its own internals safely 
        subprocess.run(["./deploy.sh"], check=True)
    except subprocess.CalledProcessError as e:
        print(f"\n[ERROR] deploy.sh failed with exit code {e.returncode}")
        sys.exit(1)

    print("\n==================================================")
    print(" Setup Complete! ")
    print(" Rebooting Raspberry Pi in 10 seconds to apply changes...")
    print("==================================================")
    
    for i in range(10, 0, -1):
        print(f"Rebooting in {i}...")
        time.sleep(1)
        
    print("Rebooting now!")
    subprocess.run(["sudo", "reboot"])

if __name__ == "__main__":
    main()
