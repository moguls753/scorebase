# frozen_string_literal: true

# PDMX Dataset Configuration
#
# Set PDMX_PATH environment variable or it defaults to ~/data/pdmx

module Pdmx
  class << self
    def root_path
      @root_path ||= Pathname.new(
        ENV.fetch("PDMX_PATH", File.expand_path("~/data/pdmx"))
      )
    end

    def exists?
      root_path.exist? && root_path.join("PDMX.csv").exist?
    end

    def setup_instructions
      <<~INSTRUCTIONS
        PDMX dataset not found at: #{root_path}

        To set up:
        1. Download PDMX from: https://zenodo.org/records/15571083
        2. Extract to: #{root_path}
        3. Run the extraction commands:

           PDMX_dir="#{root_path}"
           cd "${PDMX_dir}"
           tar -xzf data.tar.gz
           tar -xzf metadata.tar.gz
           tar -xzf mxl.tar.gz
           tar -xzf pdf.tar.gz
           tar -xzf mid.tar.gz
           tar -xzf subset_paths.tar.gz
           rm data.tar.gz metadata.tar.gz mxl.tar.gz pdf.tar.gz mid.tar.gz subset_paths.tar.gz

        4. Update paths in CSV to use absolute paths:

           sed -i "s+./data+${PDMX_dir}/data+g" "${PDMX_dir}/PDMX.csv"
           sed -i "s+./metadata+${PDMX_dir}/metadata+g" "${PDMX_dir}/PDMX.csv"
           find "${PDMX_dir}/subset_paths" -type f | xargs sed -i "s+./data+${PDMX_dir}/data+g"

        Or set a custom path with: export PDMX_PATH=/your/custom/path
      INSTRUCTIONS
    end
  end
end

# Warn in development if PDMX dataset not found
if Rails.env.development? && !Pdmx.exists?
  Rails.logger.warn "\n#{Pdmx.setup_instructions}\n"
end
