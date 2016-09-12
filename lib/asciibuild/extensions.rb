require 'asciidoctor'
require 'asciidoctor/extensions'
require 'open3'

module Asciibuild
  module Extensions
    class ConcatBlock < Asciidoctor::Extensions::BlockProcessor

      use_dsl
      named :concat
      on_context :listing

      def process parent, reader, attrs
        body = reader.lines * "\n"
        fname = attrs["file"]

        if ENV['ASCIIBUILD_SECTION'] and not parent.title == ENV['ASCIIBUILD_SECTION']
          if not (/^Before/ =~ parent.title or /^After/ =~ parent.title)
            puts "Section \"#{parent.title}\" skipped. Does not match ASCIIBUILD_SECTION=\"#{ENV['ASCIIBUILD_SECTION']}\"."
            attrs['title'] = attrs['title'] + " (skipped)"
            fname = false
          end
        end

        if fname
          if not parent.document.attributes["#{parent.title} #{fname}"]
            open(fname, 'w') do |f|
              f.write("")
            end
            parent.document.attributes["#{parent.title} #{fname}"] = true
          end

          open(fname, 'a') do |f|
            f.write(body + "\n")
          end
        end

        puts body
        create_open_block parent, ["----", body, "----"], attrs
      end

    end

    class EvalBlock < Asciidoctor::Extensions::BlockProcessor

      use_dsl
      named :asciibuild
      on_context :listing

      def before_start(cmd, parent, attrs, lines, stderr_lines)
      end

      def after_end(cmd, parent, lines, attrs)
        if attrs[2] == "Dockerfile" and attrs["run"] and not attrs["run"] == "false"
          doctitle = parent.document.attributes["doctitle"]
          cmd = if attrs["run"] == "true" then "" else attrs["run"] end
          name = if attrs["title"] then attrs["title"] else doctitle end
          docker_run = "docker run -d -i --label asciibuild.name=\"#{doctitle}\" #{attrs['run_opts']} #{attrs['image']} #{cmd}"

          puts docker_run

          rout, rerr, status = Open3.capture3(docker_run)
          puts rout, rerr
          if status == 0
            parent.document.attributes["#{name} container"] = rout.chomp
          end
          lines << "----" << "> #{docker_run}" << rout << rerr << "----"
        end
        create_open_block parent, lines, attrs
      end

      def process parent, reader, attrs
        doctitle = parent.document.attributes["doctitle"]
        lang = attrs[2]
        body = reader.lines * "\n"

        lines = []
        stderr_lines = []

        cmd = case lang
        when "Dockerfile"
          "docker build -t #{attrs['image']} #{attrs['build_opts']} -"
        when "pyspark"
          lang = "python"
          "pyspark #{attrs['spark_opts']}"
        when "spark-shell"
          lang = "scala"
          "spark-shell #{attrs['spark_opts']}"
        else
          container = attrs["container"]
          if container
            name = if not container == "true" then container else doctitle end
            container = parent.document.attributes["#{name} container"]
            "docker exec -i #{container} #{attrs['exec_opts']} #{lang}"
          else
            lang
          end
        end

        lines << "[source,#{lang}]" << "----" << body << "----"

        before_start cmd, parent, attrs, lines, stderr_lines

        if ENV['ASCIIBUILD_SECTION'] and not parent.title == ENV['ASCIIBUILD_SECTION']
          if not (/^Before/ =~ parent.title or /^After/ =~ parent.title)
            puts "Section \"#{parent.title}\" skipped. Does not match ASCIIBUILD_SECTION=\"#{ENV['ASCIIBUILD_SECTION']}\"."
            attrs['title'] = attrs['title'] + " (skipped)"
            return create_open_block parent, lines, attrs
          end
        end

        lines << ".Result of: #{cmd}" << "====" << ".STDOUT" << "----"

        puts "cat <<EOF | #{cmd}"
        puts body
        puts "EOF"

        status = 0
        Open3.popen3(cmd) do |stdin, stdout, stderr, wait_thr|
          stdin << body << "\n"
          stdin.close

          while line=stdout.gets do
            puts line
            lines << line.chomp
          end
          while line=stderr.gets do
            puts line
            stderr_lines << line.chomp
          end

          status = wait_thr.value
        end
        lines << "----"

        if not stderr_lines.size == 0
          lines << ".STDERR" << "----"
          stderr_lines.each do |l| lines << l end
          lines << "----"
        end

        if status != 0
          lines << "IMPORTANT: #{cmd} failed with #{status}"
        end

        lines << "===="

        after_end cmd, parent, lines, attrs
      end

    end

    class DocumentProcessor < Asciidoctor::Extensions::Treeprocessor
      def process document
        # document.blocks.each do |b|
        #   STDOUT.write("#{b}\n")
        #
        #   b.blocks.each do |bb|
        #     STDOUT.write("\t#{bb}\n")
        #
        #     bb.blocks.each do |bbb|
        #       STDOUT.write("\t\t#{bbb}\n")
        #     end
        #   end
        # end
        nil
      end
    end

    Asciidoctor::Extensions.register do
      treeprocessor DocumentProcessor
      block EvalBlock
      block ConcatBlock
    end
  end
end
