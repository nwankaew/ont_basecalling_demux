# Bacterial_Basecalling_Demux
Dorado basecalling pipeline for Nanopore sequencing data. The sequencing reads are basecalled by Dorado and demultiplexed. The the file in FASTQ file format were renamed into its common name follow by column alias of sampleSheet.csv  (sample.fastq.gz). Then, the final fastq file were move into its project_id (from column "sample_id").

## Files preparation


## TO Run This Script


## Output
/path/to/your/files/
├── 01.Dorado_basecall/
│   ├── dorado.bam
|   └── md5sums.txt
├── 02.Dorado_demux/
│   ├── md5sums.txt
│   ├── sample_id_1/
│   |  ├── alias.fastq.gz
│   |  └── ...
│   ├── sample_id_2/
│   |  ├── alias.fastq.gz
│   |  └── ...
├── sequencing_summary.txt
├── sampleSheet.csv
├── POD5
├── command.sh
└── command.log
