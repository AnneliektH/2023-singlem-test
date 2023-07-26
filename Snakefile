import glob

out_dir = 'output.singlem'
singlem_data_dir = config.get('singlem_data_dir', 'singlem_data')

rule all:
    input:
        "SRR8859675.otu_table.txt",


rule clone_and_create_singlem_env:
    output: 
        sdir=directory('singlem'),
        sm='singlem/bin/singlem',
    shell:
        """
        git clone https://github.com/wwood/singlem --depth 1
        cd singlem
        mamba env create -n singlem -f singlem.yml
        """

rule singlem_add_path:
    input:
        sm='singlem/bin/singlem'
    output:
        addpath=".singlem_addpath",
    conda: "singlem"
    shell:
        """
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

rule singlem_download_data:
    input:
        addpath=".singlem_addpath",
    output:
        data_touch=touch(".singlem_datadownload"),
        db="singlem_data/S3.2.0.GTDB_r214.metapackage_20230428.smpkg.zb",
        #S3.2.0.GTDB_r214.metapackage_20230428.smpkg.zb
    params:
        datadir= singlem_data_dir,
    conda: "singlem"
    shell:
        """
        singlem data --output-directory {params.datadir}
        """

rule singlem_pipe:
    input:
        addpath=".singlem_addpath",
        sra="SRR8859675",
        db=os.path.join(singlem_data_dir,"S3.2.0.GTDB_r214.metapackage_20230428.smpkg.zb"),
    output:
        otu_table="SRR8859675.otu_table.txt",
    params:
        #metapackage_path=glob.glob(os.path.join(singlem_data_dir, '*.zb'))[0],
    #    metapackage_path=os.path.join(singlem_data_dir, '*.zb')
    conda: "singlem"
    threads: 16
    shell:
       """
       export SINGLEM_METAPACKAGE_PATH={input.db}
       singlem pipe --sra-files {input.sra} \
                     --otu-table {output.otu_table} \
                     --threads {threads}
       """
