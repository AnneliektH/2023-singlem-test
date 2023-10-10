# imports
import os
import pandas as pd

# set configfile with samplenames
configfile: "config.yaml"

# Load the metadata file
metadata = pd.read_csv(config['metadata_file_path'], usecols=['Run'])

# Create a list of run ids
sra_runs = metadata['Run'].tolist()

# define output file directories
out_dir = 'output.singlem'
logs_dir = os.path.join(out_dir, 'logs')
singlem_data_dir = config.get('singlem_data_dir', 'singlem_data')

# Define samples
SAMPLES = config.get('samples', sra_runs)

wildcard_constraints:
    sample='\w+',

rule all:
    input:
#        expand(os.path.join(out_dir, "full", "{sample}.otu_table.txt"), sample=SAMPLES),
        expand(os.path.join(out_dir, "rpl11", "{sample}.otu_table.txt"), sample=SAMPLES)

# Download SRA files
rule download_sra:
    #input:
        # otu_table = os.path.join(out_dir, "rpl11", "{sample}.otu_table.txt")
        #otu_table = "output.singlem/rpl11/{sample}.otu_table.txt"
    output:
        sra = temporary("sra/{sample}")
    log:
        "logs/prefetch/{sample}.log"
    conda:
        "environment.yaml"
    shell:
        """
        mkdir -p ./sra/ 
        if [ ! -f "output.singlem/rpl11/{wildcards.sample}.otu_table.txt" ] && [ ! -f "{output.sra}" ]; then
            aws s3 cp --quiet --no-sign-request s3://sra-pub-run-odp/sra/{wildcards.sample}/{wildcards.sample} {output.sra}
        fi
        """

# Install SingleM (only has to run once)
rule clone_and_create_singlem_env:
    output: 
        sdir=directory('singlem'),
        sm_dl=".singlem_clone_and_create"
    log: os.path.join(logs_dir, 'clone_and_create_env.log')
    benchmark: os.path.join(logs_dir, 'clone_and_create_env.benchmark')
    shell:
        """
        git clone https://github.com/wwood/singlem --depth 1
        touch {output.sm_dl}
        mamba env create -n singlem -f singlem/singlem.yml
        """

# Install SingleM and add path (only has to run once)
rule singlem_add_path:
    input:
        sm_dl=".singlem_clone_and_create"
    output:
        addpath=".singlem_addpath",
    conda: "singlem"
    log: os.path.join(logs_dir, 'singlem_add_path.log')
    benchmark: os.path.join(logs_dir, 'singlem_add_path.benchmark')
    shell:
        """
        mamba install -y kingfisher # for SRA format
        set -e  # Abort the script if any command fails

        # Create an activation script for the conda environment (add to path when opening the env)
        mkdir -p "${{CONDA_PREFIX}}/etc/conda/activate.d/"

        SCRIPT_PATH="${{CONDA_PREFIX}}/etc/conda/activate.d/singlem.sh"
        touch "$SCRIPT_PATH"
        chmod +x "$SCRIPT_PATH"
        touch {output.addpath}
        cat <<EOF > "$SCRIPT_PATH"
        export PATH=$PWD/singlem/bin:\$PATH
        cd ${{PWD}}/singlem && git pull && cd -
        """

# Install SingleM and download the reference data (only has to run once)
checkpoint singlem_download_data:
    input:
        addpath=".singlem_addpath",
    output:
        db=directory(singlem_data_dir), #currently makes: singlem_data/S3.2.0.GTDB_r214.metapackage_20230428.smpkg.zb
    conda: "singlem"
    log: os.path.join(logs_dir, 'singlem_download_data.log')
    benchmark: os.path.join(logs_dir, 'singlem_download_data.benchmark')
    shell:
        """
        singlem data --output-directory {output}
        """

# Find the folder with the singleM database in it
def get_db_dirname(wildcards):
    data_dir = checkpoints.singlem_download_data.get(**wildcards).output[0]
    DB=glob_wildcards(os.path.join(data_dir, "{db}.zb")).db
    return expand(os.path.join(data_dir, "{db}.zb"), db=DB)

# Use SingleM to compare SRA file to complete reference database
rule singlem_pipe_full:
    input:
        addpath=".singlem_addpath",
        sra="{sample}",
        db=get_db_dirname,
    output:
        otu_table=os.path.join(out_dir, "full", "{sample}.otu_table.txt"),
    conda: "singlem"
    threads: 16
    log: os.path.join(logs_dir, 'singlem_pipe_full', '{sample}.log')
    benchmark: os.path.join(logs_dir, 'singlem_pipe_full', '{sample}.benchmark')
    shell:
       """
       export SINGLEM_METAPACKAGE_PATH={input.db}
       singlem pipe --sra-files {input.sra} \
                     --otu-table {output.otu_table} \
                     --threads {threads}
       """

# Use SingleM to compare SRA file to only RpL11
rule singlem_pipe_rpl:
    input:
        addpath=".singlem_addpath",
        sra="sra/{sample}",
        db=get_db_dirname,
    output:
        otu_table=protected(os.path.join(out_dir, "rpl11", "{sample}.otu_table.txt")),
    conda: "singlem"
    threads: 16
    params:
        pkg_path = "payload_directory/S3.40.ribosomal_protein_L11_rplK.spkg",
    log: os.path.join(logs_dir, 'singlem_pipe_rpl11', '{sample}.log')
    benchmark: os.path.join(logs_dir, 'singlem_pipe_rpl11', '{sample}.benchmark')
    shell:
       """
       export SINGLEM_METAPACKAGE_PATH={input.db}/{params.pkg_path}
       singlem pipe --sra-files {input.sra} \
                     --otu-table {output.otu_table} \
                     --singlem-packages {input.db}/{params.pkg_path}  \
                     --threads {threads} \
                     --no-assign-taxonomy
       """
# taxonomy assignment doesn't work for now
