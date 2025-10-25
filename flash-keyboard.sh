#!/bin/bash

set -e

# Auto-detect repository from git origin
REPO=$(git remote get-url origin | sed -E 's#.*[:/]([^/]+/[^/]+)\.git#\1#')

WORKFLOW_NAME="Build ZMK firmware"
MOUNT_POINT="/run/media/$USER/NICENANO"
TEMP_DIR=$(mktemp -d)

cleanup() {
	echo "Cleaning up temporary directory..."
	rm -rf "$TEMP_DIR"
}

trap cleanup EXIT

echo "=== ZMK Split Keyboard Firmware Flasher ==="
echo

# Download the latest firmware artifact
echo "Downloading latest firmware build..."
RUN_ID=$(gh run list --repo="$REPO" --workflow="$WORKFLOW_NAME" --limit=1 --json databaseId --jq '.[0].databaseId')

if [ -z "$RUN_ID" ]; then
	echo "Error: Could not find any workflow runs"
	exit 1
fi

echo "Found workflow run: $RUN_ID"
gh run download "$RUN_ID" --repo="$REPO" --dir "$TEMP_DIR"

# Find the firmware files
echo "Extracting firmware files..."
LEFT_FW=$(find "$TEMP_DIR" -name "*left*.uf2" | head -1)
RIGHT_FW=$(find "$TEMP_DIR" -name "*right*.uf2" | head -1)

if [ -z "$LEFT_FW" ] || [ -z "$RIGHT_FW" ]; then
	echo "Error: Could not find left and right firmware files"
	echo "Found files:"
	find "$TEMP_DIR" -name "*.uf2"
	exit 1
fi

echo "Found firmware files:"
echo "  Left:  $(basename "$LEFT_FW")"
echo "  Right: $(basename "$RIGHT_FW")"
echo

# Function to wait for mount to appear
wait_for_mount() {
	echo "Waiting for NICENANO mount to appear..."
	local timeout=60
	local elapsed=0

	while [ $elapsed -lt $timeout ]; do
		if [[ -d "$MOUNT_POINT" ]]; then
			echo "Found NICENANO at: $MOUNT_POINT"
			sleep 1
			return 0
		fi
		sleep 1
		elapsed=$((elapsed + 1))
	done

	echo "Error: Timeout waiting for NICENANO mount"
	return 1
}

# Function to wait for mount to disappear
wait_for_unmount() {
	echo "Waiting for NICENANO to disconnect..."
	local timeout=30
	local elapsed=0

	while [ $elapsed -lt $timeout ]; do
		if [[ ! -d "$MOUNT_POINT" ]]; then
			echo "NICENANO disconnected successfully"
			return 0
		fi
		sleep 1
		elapsed=$((elapsed + 1))
	done

	echo "Warning: NICENANO did not disconnect automatically"
	return 1
}

# Flash left side
echo "=== Flashing LEFT keyboard ==="
echo "Please plug in the LEFT keyboard part and put it in bootloader mode..."

if ! wait_for_mount; then
	echo "Failed to detect left keyboard"
	exit 1
fi

echo "Copying $(basename "$LEFT_FW") to $MOUNT_POINT..."
cp "$LEFT_FW" "$MOUNT_POINT/"
sync

wait_for_unmount
echo "Left keyboard flashed successfully!"
echo

# Flash right side
echo "=== Flashing RIGHT keyboard ==="
echo "Please plug in the RIGHT keyboard part and put it in bootloader mode..."

if ! wait_for_mount; then
	echo "Failed to detect right keyboard"
	exit 1
fi

echo "Copying $(basename "$RIGHT_FW") to $MOUNT_POINT..."
cp "$RIGHT_FW" "$MOUNT_POINT/"
sync

wait_for_unmount
echo "Right keyboard flashed successfully!"
echo

echo "=== Firmware flashing complete! ==="
echo "Both keyboard halves have been updated."
