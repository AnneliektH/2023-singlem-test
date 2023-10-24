import os

rule upload_to_s3:
    input:
        "output.singlem/rpl11/{wildcards.sample}.otu_table.txt"
    output:
        touch("s3_file_upload.done")
    params:
        bucket = "2023.ah.sra.singlem.results",
        # To avoid creating extra folders in s3 bucket. Just take filename.
        key = "{sample}",
    log:
        "logs/{sample}_upload_to_s3.log"
    benchmark:
        "benchmarks/{sample}_upload_to_s3_benchmark.txt"
    shell:
        """
        aws s3api put-object --bucket {params.my_s3_bucket} \
        --key {params.key} --body {input} &> {log}
        """