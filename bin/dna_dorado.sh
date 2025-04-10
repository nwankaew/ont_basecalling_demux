#!/bin/bash

# Defaullt values
indir=
outdir=
sampleCSV=
basecalled_model=
barcode_kit=
basecall_adapter_args=
demux_adapter_args=

# Define the help method
help() {
  echo "Usage: $(basename $0) [-h] [-i INDIR] [-o OUTDIR] [-s SAMPLECSV] [-m BAS
ECALLED_MODEL] [-k BARCODE_KIT] [-a BASECALL_ADAPTER_ARGS] [-d DEMUX_ADAPER_ARGS
]"
  echo "Options:"
  echo "  -h, --help                   Display this help message"
  echo "  -i, --indir,                 Set the POD5 directory"
  echo "  -o, --outdir,                Set the Output directory"
  echo "  -s, --sampleCSV,             Set the Dorado sampleCSV sheet"
  echo "  -m, --basecalled_model,      Set the Basecalling model i.g sup@v5.0.0"
  echo "  -k, --barcode_kit,           Set the Barcoding kit i.g. SQK-RBK114-96, SQK-NBD114-96"
  echo "  -a, --basecall_adapter_args  Set the Basecall_adapter_args i.g. --no-trim (NBD and RBK)"
  echo "  -d, --demux_adapter_args     Set the demux_adapter_args i.g. --barcode-both-ends (NBD), '" "' (RBK)" 
  exit 0
}

# Parse command-line options
while getopts ":hi:o:s:m:k:a:d:" opt; do
  case $opt in
    h) help ;;
    i) indir=$OPTARG ;;
    o) outdir=$OPTARG ;;
    s) sampleCSV=$OPTARG ;;
    m) basecalled_model=$OPTARG ;;
    k) barcode_kit=$OPTARG ;;
    a) basecall_adapter_args=$OPTARG ;;
    d) demux_adapter_args=$OPTARG ;;
    \?) echo "Invalid option: -$OPTARG" >&2; exit 1 ;;
  esac
done

echo; echo $(basename $0) -i $indir -o $outdir -s $sampleCSV -m $basecalled_model -k $barcode_kit -a $basecall_adapter_args -d $demux_adapter_args
# Main scipt logic
mkdir -p $outdir; echo
echo "Dorado version:                0.9.0"

mkdir -p $outdir
echo "Input directory:               $indir"
echo "Output directory:              $outdir"; echo

# Sample sheet
# sampleCSV="/home/natnicha.wan/Basecalling/basecaller/assets/sample_sheet_template.csv"
echo "Sample CSV:                    $sampleCSV"

# Basecalled model
# basecalled_model="sup@v5.0.0"
echo "Basecalled model:              $basecalled_model"

# Sequencing Kit
# barcode_kits="SQK-RBK114-96"
echo "Barcode Kits:                  $barcode_kit"; echo

# Adapter trimming
echo "Basecaller adapter options:    $basecall_adapter_args"  # --no-trim
echo "Demux adapter options:         $demux_adapter_args"     # default --no-trim, ligation=--barcode-both-ends, rapid=" "
echo

# Files check
pod5_files=$(find $in_dir -type f -name "*.pod5" | wc -l)
total=$(expr $pod5_files)
echo Found $total input files        "("POD5: $pod5_files")"; echo

# Basecalling
echo "Run Start:                    "; date; echo

mkdir -p $outdir/01.Dorado_basecall

echo; echo /data/Basecaller/dorado-0.9.0-linux-x64/bin/dorado basecaller -x cuda:all --min-qscore 10 --recursive $basecall_adapter_args $basecalled_model $indir ">" $outdir/01.Dorado_basecall/dorado.bam
echo 
/data/Basecaller/dorado-0.9.0-linux-x64/bin/dorado basecaller -x cuda:all \
  --min-qscore 10 \
  --recursive \
  $basecall_adapter_args \
  $basecalled_model $indir \
  > $outdir/01.Dorado_basecall/dorado.bam

# create md5sum for dorado file
md5sum $outdir/01.Dorado_basecall/* > $outdir/01.Dorado_basecall/filecheck.md5

# Dorado demux
mkdir -p $outdir/02.Dorado_demux
echo
if [ "$barcode_kit" == "--no-classify" ]; then
    echo "Running demux without classification..."
    # Demultiplexing without classification
    echo; echo /data/Basecaller/dorado-0.9.0-linux-x64/bin/dorado demux $barcode_kit --emit-fastq $demux_adapter_args --output-dir $outdir/02.Dorado_demux $outdir/01.Dorado_basecall/dorado.bam
    /data/Basecaller/dorado-0.9.0-linux-x64/bin/dorado demux \
        $barcode_kit \
        --emit-fastq \
        $demux_adapter_args \
        --output-dir $outdir/02.Dorado_demux \
        $outdir/01.Dorado_basecall/dorado.bam
else
    echo "Running demux with barcode classification..."
    # Demultiplexing with barcode classification and sample sheet
    echo; echo /data/Basecaller/dorado-0.9.0-linux-x64/bin/dorado demux --kit-name $barcode_kit --sample-sheet $sampleCSV --emit-fastq $demux_adapter_args --output-dir $outdir/02.Dorado_demux $outdir/01.Dorado_basecall/dorado.bam
    /data/Basecaller/dorado-0.9.0-linux-x64/bin/dorado demux \
        --kit-name $barcode_kit \
        --sample-sheet $sampleCSV \
        --emit-fastq \
        $demux_adapter_args \
        --output-dir $outdir/02.Dorado_demux \
        $outdir/01.Dorado_basecall/dorado.bam
fi

# create summary file
echo; echo /data/Basecaller/dorado-0.9.0-linux-x64/bin/dorado summary $outdir/01.Dorado_basecall/dorado.bam ">" $outdir/sequencing_summary.txt
/data/Basecaller/dorado-0.9.0-linux-x64/bin/dorado summary \
    $outdir/01.Dorado_basecall/dorado.bam > $outdir/sequencing_summary.txt

# compress demux fastq
echo
echo "compressing fastq file(s) ...  "
for f in $(ls $outdir/02.Dorado_demux/*.fastq); do gzip $f; done | xargs -I% -P4 bash -c %
echo "compressing completed "; echo

echo
files=$(cut -f1 $outdir/sequencing_summary.txt | sort | uniq | grep -v "filename" | wc -l)
echo Found $files basecalled files; echo
dupF=$(awk 'NR >1' $outdir/sequencing_summary.txt | cut -f2 | sort | uniq -c | awk '{ if ($1 > 1) print $1}' | wc -l)
echo Found $dupF duplicated read_id; echo

# Rename and Move to SI project folder
source /data/miniconda3/bin/activate ngs
echo python3 /data/Basecaller/dorado-0.9.0-linux-x64/script/rename_file.py $outdir/02.Dorado_demux/ $sampleCSV; echo
python3 /data/Basecaller/dorado-0.9.0-linux-x64/script/rename_file.py $outdir/02.Dorado_demux/ $sampleCSV

echo
echo "Run End:                 "; date; echo
