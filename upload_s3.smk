import os

rule upload_to_s3:
    input:
        otu_table = "output.singlem/rpl11/{sample}.otu_table.txt", 
        benchmark = "output.singlem/logs/singlem_pipe_rpl11/{sample}.benchmark"
    output:
        touch("s3_upload/s3_file_upload_{sample}.done")
    params:
        bucket = "2023.ah.sra.singlem.results",
        # To avoid creating extra folders in s3 bucket. Just take filename.
        key = "{sample}",
        key_bench = "{sample}.bench"
    log:
        "logs/{sample}_upload_to_s3.log"
    benchmark:
        "benchmarks/{sample}_upload_to_s3_benchmark.txt"
    shell:
        """
        aws s3api put-object --bucket {params.bucket} \
        --key {params.key} --body {input.otu_table} && \
        aws s3api put-object --bucket {params.bucket} \
        --key {params.key_bench} --body {input.benchmark} &> {log}
        """