RUN ?= true
OPTS ?=

SRC = $(shell find lib -name *.rb -print) bin/asciibuild

.PHONY: all clean gem install test

clean:
	rm -Rf *.gem vendor *.log metastore_db Dockerfile Gemfile.lock abuild
	gem uninstall -ax asciibuild

gem: clean asciibuild.gemspec $(SRC)
	gem build ./asciibuild.gemspec
	gem install ./asciibuild-*.gem -l

install: clean asciibuild.gemspec $(SRC)
	bundle install

test: install
	bundle exec asciibuild -a run=$(RUN) -a greeting $(OPTS) test/test-block-processor.adoc

all: install
