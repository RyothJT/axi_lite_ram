#!/bin/bash

# --- 1. Configuration & Paths ---
PROJECT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
cd "$PROJECT_DIR" || exit

SYN_DIR="syn"
SIM_DIR="sim"
GEN_DIR="$SIM_DIR/gen"
TOOL_DIR="$SIM_DIR/tools"
VVP_DIR="$GEN_DIR/vvp"
VCD_DIR="$GEN_DIR/vcd"

# --- 2. Storage Settings ---
MAX_WAVES=5
timestamp=$(date +"%Y%m%d_%H%M%S")

# --- 3. Input Handling & Trimming ---
if [ -z "$1" ]; then
    echo "Usage: $0 <testbench_name>"
    exit 1
fi

raw_input="${1##*/}"
tb_module="${raw_input%.*}"

tb_file="$SIM_DIR/${tb_module}.sv"
trigger_file="$TOOL_DIR/dump_trigger.sv"

# Static path for viewing, Timestamped path for backup
current_vcd="$VCD_DIR/current.vcd"
backup_vcd="$VCD_DIR/${tb_module}_${timestamp}.vcd"
vvp_out="$VVP_DIR/${tb_module}_${timestamp}.vvp"

mkdir -p "$VVP_DIR" "$VCD_DIR"

# --- 4. Validation ---
if [ ! -f "$tb_file" ]; then
    echo "Error: Testbench file not found at $tb_file"
    exit 1
fi

# --- 5. Waveform Management (Backups) ---
echo "--- Cleaning old backups in $VCD_DIR (Target: $MAX_WAVES) ---"
# We only clean the timestamped files, leaving current.vcd alone
old_waves=$(ls -1tr "$VCD_DIR/${tb_module}"_*.vcd 2>/dev/null | \
            head -n -$(($MAX_WAVES - 1)))

for f in $old_waves; do
    rm -f "$f"
done

# --- 6. Compilation ---
echo "--- Compiling: $tb_module ---"
# Note: We tell Icarus to dump directly to 'current.vcd' for the viewer
iverilog -g2012 -Wall \
    -D DUMP_FILE="\"$current_vcd\"" \
    -p VCD_ARRAY_DUMP=1 \
    -s "$tb_module" \
    -s dump_trigger \
    -o "$vvp_out" \
    "$SYN_DIR"/*.sv \
    "$tb_file" \
    "$trigger_file"

if [ $? -eq 0 ]; then
    # --- 7. Simulation & Visualization ---
    echo "--- Running Simulation ---"
    vvp -n "$vvp_out" +mda

    if [ -f "$current_vcd" ]; then
        # 1. Create the timestamped backup copy
        cp "$current_vcd" "$backup_vcd"
        echo "Saved backup to: $backup_vcd"

        # 2. Handle Surfer: Launch only if not already running
        if pgrep -x "surfer" > /dev/null; then
            echo "Surfer is already open. Please reload/refresh 'current.vcd' in the UI."
            exit 0
        else
            echo "Launching Surfer..."
            surfer "$current_vcd" &
        fi
    fi
else
    echo "Compilation failed!"
    exit 1
fi
