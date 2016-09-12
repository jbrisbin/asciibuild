RUN ?= true

.PHONY: all require clean install test

clean:
	rm -Rf *.gem

install: clean asciibuild.gemspec lib/asciibuild.rb
	gem build asciibuild.gemspec
	gem install ./asciibuild-*.gem -V -l

test: install
	asciidoctor -r asciibuild -a run=$(RUN) -a greeting -a icons=font -a source-highlighter=pygments --trace test/test-stage.adoc

all: install
