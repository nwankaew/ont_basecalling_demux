#!/bin/bash

set -euo pipefail

# Log to file
log_file="pipeline_$(date +%Y%m%d_%H%M%S).log"
exec > >(tee -a "$log_file") 2>&1

# Default values
indir=""
outdir=""
sampleCSV=""
basecalled_model=""
barcode_kit=""
basecall_adapter_args=""
demux_adapter_args=""
skip_basecaller=false

# Help function
help() {
  echo "Usage: $(basename $0) [options]"
  echo "Options:"
  echo "  -h, --help                   Display this help message"
  echo "  -i, --indir DIR              Set the POD5 input directory"
  echo "  -o, --outdir DIR             Set the output directory"
  echo "  -s, --sampleCSV FILE         Path to the Dorado sample CSV file"
  echo "  -m, --basecalled_model MODEL Basecalling model (e.g., sup@v5.0.0)"
  echo "  -k, --barcode_kit KIT        Barcoding kit (e.g., SQK-RBK114-96)"
  echo "  -a, --basecall_adapter_args  Basecalling adapter args (e.g., --no-trim)"
  echo "  -d, --demux_adapter_args     Demux adapter args (e.g., --barcode-both-ends)"
  echo "      --skip_basecaller        Skip basecalling step (flag only)"
  exit 0
}

# Parse options
while [[ "$#" -gt 0 ]]; do
  case $1 in
    -h|--help) help ;;
    -i|--indir) indir="$2"; shift ;;
    -o|--outdir) outdir="$2"; shift ;;
    -s|--sampleCSV) sampleCSV="$2"; shift ;;
    -m|--basecalled_model) basecalled_model="$2"; shift ;;
    -k|--barcode_kit) barcode_kit="$2"; shift ;;
    -a|--basecall_adapter_args) basecall_adapter_args="$2"; shift ;;
    -d|--demux_adapter_args) demux_adapter_args="$2"; shift ;;
    --skip_basecaller) skip_basecaller=true ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
  shift
done

# Log input arguments
echo "Running: $(basename $0)"
echo "Input directory:        $indir"
echo "Output directory:       $outdir"
echo "Sample CSV:             $sampleCSV"
echo "Basecalling model:      $basecalled_model"
echo "Barcode kit:            $barcode_kit"
echo "Basecall adapter args:  $basecall_adapter_args"
echo "Demux adapter args:     $demux_adapter_args"
echo "Skip basecaller:        $skip_basecaller"
echo

# Validate input
if [[ -z "$indir" || -z "$outdir" ]]; then
  echo "Error: Input/output directories are required."
  exit 1
fi

mkdir -p "$outdir"
echo "Dorado version: 0.9.0"

# Count input files
pod5_files=$(find "$indir" -type f -name "*.pod5" | wc -l)
echo "Found $pod5_files POD5 files"
echo

echo; echo $(basename $0) -i $indir -o $outdir -s $sampleCSV -m $basecalled_model -k $barcode_kit -a $basecall_adapter_args -d $demux_adapter_args --skip_basecaller=${skip_basecaller}
echo

# Basecalling step
if [[ "$skip_basecaller" == true ]]; then
  echo "Skipping basecalling step..."
else
  if [[ -z "$basecalled_model" ]]; then
    echo "Error: Basecalled model is required."
    exit 1
  fi

  mkdir -p "$outdir/01.Dorado_basecall"
  echo "Running basecalling..."
  echo; echo "/data/Basecaller/dorado-0.9.0-linux-x64/bin/dorado basecaller -x cuda:all --min-qscore 10 --recursive $basecall_adapter_args $basecalled_model $indir > $outdir/01.Dorado_basecall/dorado.bam"; echo
  /data/Basecaller/dorado-0.9.0-linux-x64/bin/dorado basecaller \
    -x cuda:all \
    --min-qscore 10 \
    --recursive \
    $basecall_adapter_args \
    "$basecalled_model" "$indir" \
    > "$outdir/01.Dorado_basecall/dorado.bam"

  md5sum "$outdir/01.Dorado_basecall/dorado.bam" > "$outdir/01.Dorado_basecall/filecheck.md5"
fi

# Demultiplexing step
mkdir -p "$outdir/02.Dorado_demux"
echo "Running demultiplexing..."
if [[ "$barcode_kit" == "--no-classify" ]]; then
  echo; echo "/data/Basecaller/dorado-0.9.0-linux-x64/bin/dorado demux $barcode_kit --emit-fastq $demux_adapter_args --output-dir $outdir/02.Dorado_demux $outdir/01.Dorado_basecall/dorado.bam"; echo
  /data/Basecaller/dorado-0.9.0-linux-x64/bin/dorado demux \
    $barcode_kit \
    --emit-fastq \
    $demux_adapter_args \
    --output-dir "$outdir/02.Dorado_demux" \
    "$outdir/01.Dorado_basecall/dorado.bam"
else
  echo; echo "/data/Basecaller/dorado-0.9.0-linux-x64/bin/dorado demux --kit-name $barcode_kit --sample-sheet $sampleCSV --emit-fastq $demux_adapter_args --output-dir $outdir/02.Dorado_demux $outdir/01.Dorado_basecall/dorado.bam"; echo
  /data/Basecaller/dorado-0.9.0-linux-x64/bin/dorado demux \
    --kit-name "$barcode_kit" \
    --sample-sheet "$sampleCSV" \
    --emit-fastq \
    $demux_adapter_args \
    --output-dir "$outdir/02.Dorado_demux" \
    "$outdir/01.Dorado_basecall/dorado.bam"
fi

# Generate summary
/data/Basecaller/dorado-0.9.0-linux-x64/bin/dorado summary \
  "$outdir/01.Dorado_basecall/dorado.bam" > "$outdir/sequencing_summary.txt"

# Gzip all fastq in $outdir/02.Dorado_demux
echo "GZIP fastq files..."; echo
find "$outdir/02.Dorado_demux" -type f -name "*.fastq" -exec gzip {} \;

# Check results
files=$(cut -f1 "$outdir/sequencing_summary.txt" | grep -v "filename" | sort -u | wc -l)
echo "Basecalled files: $files"
dupF=$(awk 'NR>1' "$outdir/sequencing_summary.txt" | cut -f2 | sort | uniq -c | awk '$1 > 1' | wc -l)
echo "Duplicated read IDs: $dupF"

# Rename fastqs
source /data/miniconda3/bin/activate ngs
python3 /data/Basecaller/dorado-0.9.0-linux-x64/script/rename_file.py \
  "$outdir/02.Dorado_demux/" "$sampleCSV"

echo "Pipeline completed on: $(date)"
