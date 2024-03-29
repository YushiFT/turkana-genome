#!/bin/bash
#SBATCH --job-name=22rebase               # create a short name for your job
#SBATCH --nodes=1                          # node count
#SBATCH --ntasks-per-node=1                # total number of tasks across all nodes
#SBATCH --cpus-per-task=4                  # cpu-cores per task (>1 if multithread tasks)
#SBATCH --mem=70G                          # memory per node
#SBATCH --time=72:00:00 --qos=1wk          # total run time limit (HH:MM:SS)
#SBATCH --mail-type=begin                  # send mail when process begins
#SBATCH --mail-type=end                    # send email when job ends
#SBATCH --mail-user=yushit@princeton.edu

# Step   I: Identify duplicated reads with sorted bam or sam files
# Step  II: Recalibrate base quality scores
# Step III: Calling GATK variants and export VCF
# High coverage ones includes barcode as
# 192, 169, 368, 345, 281, 381, 294, 234, 323, 165, 338, 334, 370,
# 308, 332, 211, 258, 203, 218, 249, 245, 242, 202, 304, 235, 309,
# 330, 205
# define file head
barcode=Sample_Barcode-22
# define input
in_fastq1=/Genomics/ayroleslab2/alea/archive_raw_fastq/Project_AYR_13970_B01_NAN_Lane.2019-04-19/$barcode/fastq/*R1.fastq.gz
in_fastq2=/Genomics/ayroleslab2/alea/archive_raw_fastq/Project_AYR_13970_B01_NAN_Lane.2019-04-19/$barcode/fastq/*R2.fastq.gz
in_picard=/Genomics/grid/users/yushit/.local/bin/picard.jar
in_gatk=/Genomics/grid/users/yushit/.local/bin/gatk-4.1.3.0
in_sambamba=/Genomics/grid/users/yushit/.local/bin/sambamba-0.7.0
in_genome=/Genomics/ayroleslab2/yushi/ref/hg38_all_chr.fa
in_variants=/Genomics/ayroleslab2/yushi/ref/public_datasets/resources_broad_hg38_v0_Homo_sapiens_assembly38.dbsnp138.vcf
# define output
out_fastq1=/scratch/tmp/yushi/$barcode.trim.R1.fastq.gz
out_fastq2=/scratch/tmp/yushi/$barcode.trim.R2.fastq.gz
out_sam=/scratch/tmp/yushi/$barcode.hg38.sam
out_bam=/scratch/tmp/yushi/$barcode.hg38.bam
out_bam_sorted=/scratch/tmp/yushi/$barcode.hg38.sorted.bam
out_bam_duplicates=/scratch/tmp/yushi/$barcode.hg38.dup.bam
out_txt_dupmetrics=/scratch/tmp/yushi/$barcode.hg38.dup.txt
out_bam_readgroups=/scratch/tmp/yushi/$barcode.hg38.reg.bam
out_table_recalibr=/scratch/tmp/yushi/$barcode.rbqs.table
out_bam_recalibrat=/scratch/tmp/yushi/$barcode.rbqs.bam
out_g_vcf=/scratch/tmp/yushi/turkana_wgs_vcf/$barcode.hg38.g.vcf

module load java
module load samtools

# Step I
echo 'samtools sorting...' # sort bam file

samtools sort -m 3G -o $out_bam_sorted $out_bam

echo 'picard duplications...' # run picard to mark duplicates

java -Xmx66g -jar $in_picard MarkDuplicates I=$out_bam_sorted O=$out_bam_duplicates M=$out_txt_dupmetrics

rm -f $out_bam_sorted

# Step II
echo 'adding read groups...'

java -Xmx66g -jar $in_picard AddOrReplaceReadGroups I=$out_bam_duplicates O=$out_bam_readgroups SO=coordinate RGLB=$barcode RGPL=illumina RGPU=turkana RGSM=$barcode

rm -f $out_bam_duplicates
rm -f $out_txt_dupmetrics

echo 'pre-indexing...'

$in_sambamba index -t 4 $out_bam_readgroups

echo 'recalibrating base quality scores...' # sort bam file

$in_gatk/gatk BaseRecalibrator  -I $out_bam_readgroups -R $in_genome --known-sites $in_variants -O $out_table_recalibr

$in_gatk/gatk ApplyBQSR -R $in_genome -I $out_bam_readgroups -bqsr $out_table_recalibr -O $out_bam_recalibrat

#rm -f $out_bam_readgroups

echo 'post-indexing...'

$in_sambamba index -t 4 $out_bam_recalibrat

# Step III

echo 'calling GATK variants as VCF and zip...'

$in_gatk/gatk --java-options "-Xmx60g" HaplotypeCaller -R $in_genome -I $out_bam_recalibrat -O $out_g_vcf -ERC GVCF --max-alternate-alleles 2 --native-pair-hmm-threads 4
