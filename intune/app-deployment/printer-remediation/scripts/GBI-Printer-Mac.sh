#!/bin/bash

# GBI Printer - VersaLink C500 - test deployment
# Idempotent create-or-update pattern (matches "UK Main Printer - 02 - Mac copy.sh").
#
# PPD filename confirmed against a live US Mac laptop already carrying
# "Xerox Universal macOS Print Drivers 5.10.1" (Required, Mac Devices - All Regions):
#   ls -1 "/Library/Printers/PPDs/Contents/Resources/" | grep -i versalink
#   -> Xerox VersaLink C500.gz

PRINTER_QUEUE="GBI-Printer"
PRINTER_DISPLAY_NAME="GBI Printer"
PRINTER_LOCATION="Test"
PRINTER_URI="ipp://192.168.214.112/ipp/print"
PPD_PATH="/Library/Printers/PPDs/Contents/Resources/Xerox VersaLink C500.gz"

LPADMIN="/usr/sbin/lpadmin"
LPSTAT="/usr/bin/lpstat"

echo "Checking Xerox driver..."

if [ ! -f "$PPD_PATH" ]; then
    echo "ERROR: Xerox VersaLink C500 driver is not installed at $PPD_PATH."
    echo "Confirm the real PPD filename with: ls -1 \"/Library/Printers/PPDs/Contents/Resources/\" | grep -i versalink"
    exit 1
fi

echo "Xerox driver found."

if "$LPSTAT" -p "$PRINTER_QUEUE" >/dev/null 2>&1; then
    echo "Printer queue already exists. Updating configuration."

    "$LPADMIN" \
        -p "$PRINTER_QUEUE" \
        -D "$PRINTER_DISPLAY_NAME" \
        -L "$PRINTER_LOCATION" \
        -E \
        -v "$PRINTER_URI" \
        -P "$PPD_PATH"
else
    echo "Creating printer queue."

    "$LPADMIN" \
        -p "$PRINTER_QUEUE" \
        -D "$PRINTER_DISPLAY_NAME" \
        -L "$PRINTER_LOCATION" \
        -E \
        -v "$PRINTER_URI" \
        -P "$PPD_PATH"
fi

RESULT=$?

if [ "$RESULT" -eq 0 ] && "$LPSTAT" -p "$PRINTER_QUEUE" >/dev/null 2>&1; then
    echo "Printer installed or updated successfully."
    "$LPSTAT" -p "$PRINTER_QUEUE"
    "$LPSTAT" -v "$PRINTER_QUEUE"
    exit 0
else
    echo "ERROR: Printer installation or update failed."
    exit 1
fi
