require 'optparse'
require 'fileutils'
require 'find'
require 'bundler'

options = {}
options[:exclude] = []

opt_parser = OptionParser.new do |opts|
  opts.banner = 'Usage: origen archive [options]'
  opts.on('--local', 'Install gems within your app so that it can run completely standalone, no archive is created') { options[:local] = true }
  opts.on('--no-local', "Reverses a previously executed 'origen archive --local' operation, returning the app to use a conventional gem installation") { options[:no_local] = true }
  opts.on('-e', '--exclude DIR', 'Exclude the given directory from the archive, e.g. --exclude simulation') { |dir| options[:exclude] << dir }
end
opt_parser.parse! ARGV

origen_binstub = File.join(Origen.root, 'lbin', 'origen')

unless  File.exist?(origen_binstub) && File.read(origen_binstub) =~ /This file was generated by Origen/
  puts 'An archive can only be created after your application is running the latest Origen boot system,'
  puts 'run the following command to update your application and then try again:'
  puts
  puts '  origen setup'
  puts
  exit 1
end

if options[:no_local]
  Dir.chdir Origen.root do
    dir = File.join('vendor', 'gems')
    FileUtils.rm_rf(dir) if File.exist?(dir)
  end
  passed = true
  Bundler.with_clean_env do
    passed = system('origen -v')
  end
  if passed
    Origen.log.success 'Local gems have been removed and your application has been restored to use a conventional gem installation.'
    exit 0
  else
    Origen.log.error 'A problem was encountered when trying to boot your application after removing local gems!'
    exit 1
  end
end

Origen.log.info 'Preparing the workspace' unless options[:local]
tmp1 = File.join(Origen.root, '..', "#{Origen.app.name}_copy")
name = "#{Origen.app.name}-#{Origen.app.version}"
tmpdir = File.join(Origen.root, 'tmp')
tmp = File.join(tmpdir, name)
archive = File.join(Origen.root, 'tmp', "#{name}.origen")
unless options[:local]
  FileUtils.rm_rf(tmp1) if File.exist?(tmp1)
  FileUtils.rm_rf(tmp) if File.exist?(tmp)
  FileUtils.rm_rf(archive) if File.exist?(archive)
end

exclude_dirs = ['.bundle', 'output', 'tmp', 'web', 'waves', '.git', '.ref', 'dist', 'log', '.lsf', '.session'] + options[:exclude]

unless options[:local]
  begin
    Origen.log.info 'Creating a copy of the application'
    if Origen.os.linux?
      Dir.chdir Origen.root do
        cmd = "rsync -av --progress . tmp/#{name} --exclude /tmp"
        exclude_dirs.each do |dir|
          cmd += " --exclude /#{dir}"
        end
        passed = system cmd
        unless passed
          Origen.log.error 'A problem was encountered when creating a copy of your application, archive aborted!'
          exit 1
        end
      end
    else
      FileUtils.mkdir_p(tmp1)
      FileUtils.cp_r "#{Origen.root}/.", tmp1
      FileUtils.mv tmp1, tmp
    end
    # Remove all .svn or .SYNC directories
    Find.find(tmp) do |path|
      n = File.basename(path)
      if FileTest.directory?(path) && (n == '.svn' || n == '.SYNC')
        puts "Removing: #{path}"
        FileUtils.remove_dir(path)
      end
    end
  ensure
    FileUtils.rm_rf(tmp1) if File.exist?(tmp1)
  end
end

Origen.log.info 'Fetching all required gems' unless options[:local]
dir = options[:local] ? Origen.root : tmp
Dir.chdir dir do
  # When archiving, also include copies of all gem packages for other platforms, this will help if the
  # archive needs to run on a different platform to the one used to create it in the future
  unless options[:local]
    Bundler.with_clean_env do
      FileUtils.rm_rf('.bundle') if File.exist?('.bundle')
      system 'hash -r'  # Ignore fail if not on bash

      passed = system "GEM_HOME=#{File.expand_path(Origen.site_config.gem_install_dir)} bundle package --all --all-platforms --no-install"
      unless passed
        Origen.log.error 'A problem was encountered when packaging the gems, archive aborted!'
        exit 1
      end
      FileUtils.rm_rf('.bundle') if File.exist?('.bundle')
    end
  end

  Origen.log.info 'Installing gems into the application (this could take a while)'
  FileUtils.mkdir_p(File.join('vendor', 'gems'))
  require 'origen/boot/app'
  begin
    Origen::Boot.setup(dir)
    Origen::Boot.setup_bundler(dir)
  rescue Exception => e
    Origen.log.error e.to_s
    Origen.log.error 'A problem was encountered setting up the workspace, archive aborted!'
    exit 1
  end
  FileUtils.touch('.origen_archive') unless options[:local]

  Bundler.with_clean_env do
    passed = system('bundle') && system('origen -v')
    unless passed
      Origen.log.error 'A problem was encountered installing the gem bundle, archive aborted!'
      exit 1
    end
  end

  unless options[:local]
    Origen.log.info 'Removing all temporary and output files'
    exclude_dirs.each do |dir|
      if File.exist?(dir)
        if File.symlink?(dir)
          FileUtils.rm(dir)
        else
          FileUtils.rm_rf(dir)
        end
      end
    end
  end
end

if options[:local]
  Origen.log.success 'Gems have been successfully installed to your application'
  Origen.log.success ''
  Origen.log.success 'If you ran this in error or otherwise want to undo it, run the following command:'
  Origen.log.success '  origen archive --no-local'
  Origen.log.success ''
else
  Origen.log.info 'Creating archive'
  Dir.chdir tmpdir do
    FileUtils.rm_rf('.bundle') if File.exist?('.bundle')
    passed = system "tar -cvzf #{name}.origen ./#{name}"
    unless passed
      Origen.log.error 'A problem was encountered creating the tarball, archive aborted!'
      exit 1
    end

    Origen.log.info 'Cleaning up'
    FileUtils.rm_rf(name)
  end

  puts
  begin
    size = `du -sh tmp/#{name}.origen`.split(/\s+/).first
    Origen.log.success "Your application archive is complete and is #{size}B in size"
  rescue
    Origen.log.success 'Your application archive is complete'
  end
  Origen.log.success archive
end