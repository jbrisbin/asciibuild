require 'asciidoctor'
require 'asciidoctor/extensions'
require 'open3'

def include_section? parent, attrs
  sections = if parent.document.attributes["sections"]
    parent.document.attributes["sections"].split(/,[ ]*/)
  else
    []
  end

  incl_sect = sections.empty?
  sections.each do |s|
    if not incl_sect and Regexp.new(s) =~ parent.title
      incl_sect = true
    end
  end

  incl_sect or (not parent.document.attributes["error"] and (/^Before/ =~ parent.title or /^After/ =~ parent.title))
end

module Asciibuild
  module Extensions
    class ConcatBlock < Asciidoctor::Extensions::BlockProcessor

      use_dsl
      named :concat
      on_context :listing

      def process parent, reader, attrs
        doctitle = parent.document.attributes["doctitle"]
        body = reader.read

        puts ""
        puts "#{doctitle} > #{parent.title} > #{attrs['title']}"
        puts (">" * 80)

        fname = if not include_section?(parent, attrs)
          if parent.document.attributes["error"]
            puts "Section \"#{parent.title}\" skipped due to previous error."
            attrs['title'] = 'icon:pause-circle[role=red] ' + attrs['title'] + " (previous error)"
          else
            sections = parent.document.attributes["sections"].split(/,[ ]*/)
            puts "Section \"#{parent.title}\" skipped. Does not match #{sections}."
            attrs['title'] = 'icon:pause-circle[role=yellow] ' + attrs['title']
          end
          false
        else
          attrs["file"]
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
          puts body
        end

        puts ("<" * 80)

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
        if attrs[2] == 'Dockerfile' and attrs['run'] and not attrs['run'] == 'false'
          doctitle = parent.document.attributes['doctitle']
          cmd = if attrs['run'] == 'true' then '' else attrs['run'] end
          name = if attrs['original_title'] then attrs['original_title'] else doctitle end
          docker_run = "docker run -d -i --label asciibuild.name=\"#{doctitle}\" #{attrs['run_opts']} #{attrs['image']} #{cmd}"

          puts docker_run

          rout, rerr, status = Open3.capture3(docker_run)
          puts rout, rerr
          if status == 0
            parent.document.attributes["#{name} container"] = rout.chomp
          else
            parent.document.attributes["error"] = true
          end
          lines << "----" << "> #{docker_run}" << rout << rerr << "----"
        end
        create_open_block parent, lines, attrs
      end

      def process parent, reader, attrs
        doctitle = parent.document.attributes["doctitle"]
        attrs['original_title'] = attrs['title']
        lang = attrs[2]
        body = reader.read

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
          if attrs['container']
            name = if attrs['container'] == 'true'
              doctitle
            else
              attrs['container']
            end
            container_id = parent.document.attributes["#{name} container"]
            "docker exec -i #{container_id} #{attrs['exec_opts']} #{lang}"
          else
            lang
          end
        end

        lines = ["[source,#{lang}]", "----", body, "", "----"]

        puts ""
        puts "#{doctitle} > #{parent.title} > #{attrs['title']}"
        puts (">" * 80)

        before_start cmd, parent, attrs, lines, stderr_lines

        if not include_section?(parent, attrs)
          if parent.document.attributes["error"]
            puts "Section \"#{parent.title}\" skipped due to previous error."
            attrs['title'] = 'icon:pause-circle[role=red] ' + attrs['title'] + " (previous error)"
          else
            sections = parent.document.attributes["sections"].split(/,[ ]*/)
            puts "Section \"#{parent.title}\" skipped. Does not match #{sections}."
            attrs['title'] = 'icon:pause-circle[role=yellow] ' + attrs['title']
          end
          return create_open_block parent, lines, attrs
        end

        lines << ".#{cmd}" << "----"

        puts "cat <<EOF | #{cmd}"
        puts body
        puts "EOF"
        puts ""

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
        puts ("<" * 80)

        if not stderr_lines.size == 0
          lines << ".STDERR" << "----"
          stderr_lines.each do |l| lines << l end
          lines << "----"
        end

        if status != 0
          lines << "IMPORTANT: #{cmd} failed with #{status}"
          parent.document.attributes["error"] = true
          attrs['title'] = 'icon:exclamation-circle[role=red] ' + attrs['title']
        else
          attrs['title'] = 'icon:check-circle[role=green] ' + attrs['title']
        end

        after_end cmd, parent, lines, attrs
      end

    end

    class DocumentProcessor < Asciidoctor::Extensions::Treeprocessor
      def process document
        # puts document
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
