# -*- snakemake -*-
import os
from snakemake.workflow import workflow
from snakemakelib.config import update_sml_config, get_sml_config
from snakemakelib.bio.ngs.targets import generic_target_generator

def _merge_suffix(aligner, quantification=[]):
    align_cfg = get_sml_config('bio.ngs.align.' + aligner)
    if aligner == "star":
        return align_cfg['align']['suffix'].replace('.bam', '_unique.bam')
    elif aligner in ["bowtie", "bowtie2"]:
        return '_unique.bam'

def _merge_tx_suffix(aligner, quantification=[]):
    align_cfg = get_sml_config('bio.ngs.align.' + aligner)
    if aligner == "star":
        return ".Aligned.toTranscriptome.out_unique.bam"

def _find_transcript_bam(wildcards):
    ngs_cfg = get_sml_config('bio.ngs.settings')
    picard_cfg = get_sml_config('bio.ngs.qc.picard')
    sources = generic_target_generator(tgt_re=ngs_cfg['sampleorg'].run_id_re, target_suffix = _merge_tx_suffix(ngs_cfg['aligner'], ngs_cfg['rnaseq']['quantification']), filter_suffix = ngs_cfg['read1_label'] + ngs_cfg['fastq_suffix'], **ngs_cfg)
    sources = [src for src in sources if os.path.dirname(src).startswith(wildcards.prefix)]
    return sources

def find_scrnaseq_merge_inputs(wildcards):
    """Find platform unit specific aligned bam files as input to picard
merge.
    """
    ngs_cfg = get_sml_config('bio.ngs.settings')
    picard_cfg = get_sml_config('bio.ngs.qc.picard')
    sources = generic_target_generator(tgt_re=ngs_cfg['sampleorg'].run_id_re, target_suffix = _merge_tx_suffix(ngs_cfg['aligner'], ngs_cfg['rnaseq']['quantification']), filter_suffix = ngs_cfg['read1_label'] + ngs_cfg['fastq_suffix'], **ngs_cfg)
    sources = [src for src in sources if os.path.dirname(src).startswith(wildcards.prefix)]
    return sources

config_default = {
    'bio.ngs.settings' : {
        'aligner' : 'bowtie',
    },
    'bio.ngs.qc.picard' : {
        'merge_sam' : {
            'label' : 'merge',
            'inputfun' : find_scrnaseq_merge_inputs,
        },
    },
}

update_sml_config(config_default)
ngs_cfg = get_sml_config('bio.ngs.settings')
aligner = ngs_cfg['aligner']

# Include necessary snakemakelib rules
p = os.path.join(os.pardir, os.pardir, 'rules')
include: os.path.join(p, 'settings.rules')
include: os.path.join(p, 'utils.rules')
align_include = os.path.join(p, "bio/ngs/align", aligner + ".rules")
include: align_include
include: os.path.join(p, "bio/ngs/tools", "bamtools.rules")
include: os.path.join(p, "bio/ngs/qc", "rseqc.rules")
include: os.path.join(p, "bio/ngs/qc", "picard.rules")
include: os.path.join(p, "bio/ngs/tools", "samtools.rules")
include: os.path.join(p, "bio/ngs/rnaseq", "rpkmforgenes.rules")
include: os.path.join(p, "bio/ngs/rnaseq", "rsem.rules")
if aligner in ["bowtie", "bowtie2"]:
    ruleorder: bamtools_filter > picard_merge_sam > picard_sort_bam > bowtie_align

if workflow._workdir is None:
    raise Exception("no workdir set, or set after include of 'scrnaseq.workflow'; set workdir before include statement!")
path = workflow._workdir

picard_config = get_sml_config("bio.ngs.qc.picard")

# Additional merge rule for transcript alignment files
rule scrnaseq_picard_merge_sam_transcript:
    """scrnaseq picard: merge sam files from transcript alignments.

    NB: always outputs bam files!
    """
    params: cmd = picard_config['cmd'] + "MergeSamFiles",
            options = " ".join([picard_config['options'],
                                picard_config['merge_sam']['options']])
    input: _find_transcript_bam
    output: merge="{path}" + os.sep + "{prefix}." + "merge.tx.bam"
    run: 
      if (len(input) > 1):
          inputstr = " ".join(["INPUT={}".format(x) for x in input])
          shell("{cmd} {ips} OUTPUT={out} {opt}".format(cmd=params.cmd, ips=inputstr, out=output.merge, opt=params.options))
      else:
          os.symlink(os.path.relpath(input[0], wildcards.path), output.merge)

ALIGN_TARGETS = generic_target_generator(tgt_re = ngs_cfg['sampleorg'].run_id_re, src_re = ngs_cfg['sampleorg'].raw_run_re, target_suffix = _merge_suffix(aligner), filter_suffix = ngs_cfg['read1_label'] + ngs_cfg['fastq_suffix'],  **ngs_cfg)

RSEQC_TARGETS = generic_target_generator(tgt_re = ngs_cfg['sampleorg'].sample_re, target_suffix = '.merge_rseqc/rseqc_qc_8.txt', src_re = ngs_cfg['sampleorg'].raw_run_re, filter_suffix = ngs_cfg['read1_label'] + ngs_cfg['fastq_suffix'], **ngs_cfg)

RPKMFORGENES_TARGETS = generic_target_generator(tgt_re = ngs_cfg['sampleorg'].sample_re, target_suffix = '.merge.rpkmforgenes', src_re = ngs_cfg['sampleorg'].raw_run_re, filter_suffix = ngs_cfg['read1_label'] + ngs_cfg['fastq_suffix'], **ngs_cfg) if 'rpkmforgenes' in ngs_cfg['rnaseq']['quantification']  else []

RSEM_TARGETS = generic_target_generator(tgt_re = ngs_cfg['sampleorg'].sample_re, target_suffix = '.merge.tx.isoforms.results', src_re = ngs_cfg['sampleorg'].raw_run_re, filter_suffix = ngs_cfg['read1_label'] + ngs_cfg['fastq_suffix'], **ngs_cfg) if 'rsem' in ngs_cfg['rnaseq']['quantification']  else []

REPORT_TARGETS = ['report/star.Aligned.out.csv', 'report/star.Aligned.out.mapping_summary.html']

# All rules
rule scrnaseq_all:
    """Run scRNAseq pipeline"""
    input: ALIGN_TARGETS + RSEQC_TARGETS + RPKMFORGENES_TARGETS + RSEM_TARGETS + REPORT_TARGETS

rule scrnaseq_align:
    """Run alignments"""
    input: ALIGN_TARGETS

rule scrnaseq_rseqc:
    """Run RSeQC"""
    input: RSEQC_TARGETS

rule scrnaseq_rpkmforgenes:
    """Run rpkmforgenes"""
    input: RPKMFORGENES_TARGETS

rule scrnaseq_rsem:
    """Run rpkmforgenes"""
    input: RSEM_TARGETS
    
rule scrnaseq_targets:
    """Print targets """
    run:
        print (ALIGN_TARGETS)
        print (RSEQC_TARGETS)
        print (RPKMFORGENES_TARGETS)
        print (RSEM_TARGETS)

rule scrnaseq_clean:
    """Clean working directory. WARNING: will remove all files except
    (.fastq|.fastq.gz) and csv files
    """
    params: d = workflow._workdir
    shell: 'for f in `find  {params.d} -type f -name "*" | grep -v ".fastq$" | grep -v ".fastq.gz$" | grep -v ".csv$"`; do echo removing $f; rm -f $f; done'
