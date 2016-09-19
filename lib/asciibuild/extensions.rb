require 'asciidoctor'
require 'asciidoctor/extensions'
require 'open3'
require 'mustache'

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

def get_lang lang
  case lang
  when 'pyspark'
    'python'
  when 'spark-shell'
    'scala'
  else
    lang
  end
end

def write_file attrs, default_name, body
  name = attrs['file'] ||= default_name
  mode = if attrs['overwrite'] == 'false' then File::WRONLY|File::CREAT|File::EXCL else 'w' end
  open(name, mode) do |f|
    f.write(body + "\n")
  end
end

module Asciibuild
  module Extensions
    class ConcatBlock < Asciidoctor::Extensions::BlockProcessor
      # BlockProcessor to concatenate content into a single file.
      # It allows you to break up sections of a file into separate listing blocks and aggregate them together
      # into a single file you can reference later in the process.
      #
      # .Add function to file
      # [concat,bash,file=utility.sh]
      # ----
      # #!/bin/bash
      #
      # fun greet() {
      #   echo 'Hello World'
      # }
      # ----
      #
      # .Add call to file
      # [concat,bash,file=utility.sh]
      # ----
      # echo 'Hello World'
      # ----
      #
      # After the document is processed, a file in the working directory will exist named "utility.sh" which
      # will consist of the content of all the listing blocks in that section that use the same file name.

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
      # BlockProcessor to make the content of listing blocks executable. Has built-in support for:
      #
      # * `Dockerfile`
      # * `spark-shell` (Scala)
      # * `pyspark` (Python)
      # * `erlang`
      # * Any interpreted language that accepts `STDIN`
      #
      # To use, add the `[asciibuild,Language]` style to a listing block.
      #
      # .Run a bash script
      # [asciibuild,bash]
      # ----
      # echo 'Hello World'
      # ----
      #
      # If using a language like BASH or Python, the language's interpreter should accept `STDIN` as
      # input and be found in the `PATH`.


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
        lang = get_lang attrs[2]
        doctitle = parent.document.attributes['doctitle']
        if not attrs['title']
          attrs['title'] = lang
        end
        attrs['original_title'] = attrs['title']

        if not include_section?(parent, attrs)
          if parent.document.attributes["error"]
            puts "Section \"#{parent.title}\" skipped due to previous error."
            attrs['title'] = 'icon:pause-circle[role=red] ' + attrs['title'] + " (previous error)"
          else
            sections = parent.document.attributes["sections"].split(/,[ ]*/)
            puts "Section \"#{parent.title}\" skipped. Does not match #{sections}."
            attrs['title'] = 'icon:pause-circle[role=yellow] ' + attrs['title']
          end
          lang = get_lang attrs[2]
          return create_open_block parent, ["[source,#{lang}]", "----"] + reader.lines + ["----"], attrs
        end

        body = Mustache.render(reader.read, parent.document.attributes)

        lines = []
        stderr_lines = []

        cmd = case attrs[2]
        when 'Dockerfile'
          if not attrs['image']
            raise 'Missing image name. Add attribute of image={name} to the [asciibuild,Dockerfile] style.'
          end
          fname = attrs['file'] ||= 'Dockerfile'
          write_file attrs, 'Dockerfile', body
          "docker build -t #{attrs['image']} #{attrs['build_opts']} -f #{fname} ."
        when 'erlang'
          write_file attrs, 'escript.erl', body
          "escript #{name} #{attrs['escript_opts']}"
        when 'pyspark'
          "pyspark #{attrs['spark_opts']}"
        when 'spark-shell'
          "spark-shell #{attrs['spark_opts']}"
        when 'bash'
          "bash -exs #{attrs['bash_opts']}"
        else
          attrs[2]
        end
        # Check to see if we run inside a container
        if attrs['container']
          name = if attrs['container'] == 'true' then doctitle else attrs['container'] end
          container_id = parent.document.attributes["#{name} container"]
          cmd = "docker exec -i #{container_id} #{attrs['exec_opts']} #{cmd}"
        end

        lines = ["[source,#{lang}]", "----", body, "", "----"]

        puts ""
        puts "#{doctitle} > #{parent.title} > #{attrs['title']}"
        puts (">" * 80)

        before_start cmd, parent, attrs, lines, stderr_lines

        lines << ".#{cmd}" << "----"

        puts body
        puts "> #{cmd}"
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

    Asciidoctor::Extensions.register do
      block EvalBlock
      block ConcatBlock
    end
  end
end
