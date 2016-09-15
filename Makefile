RUN ?= true
OPTS ?=

SRC = $(shell find lib -name *.rb -print) bin/asciibuild

.PHONY: all clean install test

clean:
	rm -Rf *.gem vendor *.log metastore_db Dockerfile Gemfile.lock abuild
	gem uninstall -x asciibuild

install: clean asciibuild.gemspec $(SRC)
	bundle install

test: install
	bundle exec asciibuild -a run=$(RUN) -a greeting $(OPTS) test/test-block-processor.adoc

all: install
