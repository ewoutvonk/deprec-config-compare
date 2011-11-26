# Copyright (c) 2009-2011 by Ewout Vonk. All rights reserved.

# prevent loading when called by Bundler, only load when called by capistrano
if caller.any? { |callstack_line| callstack_line =~ /^Capfile:/ }
  unless Capistrano::Configuration.respond_to?(:instance)
    abort "deprec-config-compare requires Capistrano 2"
  end

  require 'capistrano'

  module Deprec
    module ConfigCompare
      def compare_files(app, local_file, remote_file)
        stage = exists?(:stage) ? fetch(:stage).to_s : ''
        tmpdir = "/tmp/#{Time.now.strftime("%Y%m%d%H%M%S")}.deprec"
  
        FileUtils.mkdir_p(tmpdir)
        begin
          download(remote_file, File.join(tmpdir, "$CAPISTRANO:HOST$#{remote_file.gsub(/[\/\.]/, '_')}.tmp"), { :via => :scp, :silent => true })
        rescue Exception
          # ignore errors, it just means the file doesn't exist on a specific server. This can be the case if the file only
          # gets uploaded to servers with a specific role for example.
        end
        Dir.new(tmpdir).entries.collect { |e| File.file?(File.join(tmpdir, e)) ? File.join(tmpdir, e) : nil }.compact.each do |tmp_file|
          hostname = File.basename(tmp_file).split(/_/).first
          local_file_full_path = (File.exists?(File.join('config', stage, hostname, app.to_s, local_file)) ?
                                  File.join('config', stage, hostname, app.to_s, local_file) :
                                  File.join('config', stage, app.to_s, local_file))
          puts `diff -u #{local_file_full_path} #{tmp_file}` if File.exists?(local_file_full_path)
          FileUtils.rm_f(tmp_file)
        end
        FileUtils.rmdir(tmpdir)
      end
    end
  end

  Capistrano::EXTENSIONS[:deprec2].send(:include, Deprec::ConfigCompare)

  def define_config_compare_tasks(base_namespace)
    Capistrano::Configuration.instance.send(base_namespace).namespaces.keys.each do |ns_name|
      ns = Capistrano::Configuration.instance.send(base_namespace).send(ns_name)
      Capistrano::Configuration.instance.namespace base_namespace do
        namespace ns_name do
          unless ns.respond_to?(:diff_config_project)
            desc "perform local/remote diff on project configs for :#{ns_name}"
            task :diff_config_project do
              PROJECT_CONFIG_FILES[ns_name].each do |config_file|
                deprec2.compare_files(ns_name, config_file[:path], config_file[:path])
              end if defined?(PROJECT_CONFIG_FILES) && PROJECT_CONFIG_FILES[ns_name]
            end
          end

          unless ns.respond_to?(:diff_config_system)
            desc "perform local/remote diff on system configs for :#{ns_name}"
            task :diff_config_system do
              SYSTEM_CONFIG_FILES[ns_name].each do |config_file|
                deprec2.compare_files(ns_name, config_file[:path], config_file[:path])
              end if defined?(SYSTEM_CONFIG_FILES) && SYSTEM_CONFIG_FILES[ns_name]
            end
          end

          unless ns.respond_to?(:diff_config)
            desc "perform local/remote diff on all configs for :#{ns_name}"
            task :diff_config do
              diff_config_system
              diff_config_project
            end
          end
        end
      end
    end

    Capistrano::Configuration.instance(:must_exist).load do 
      namespace base_namespace do
        desc "compare configs for the current stage for all defined roles"
        task :diff_configs do
          top.send(base_namespace).namespaces.keys.each do |ns_name|
            ns = top.send(base_namespace).send(ns_name)
            recipe_declared_roles = ns.tasks.collect { |k,v| v.options.has_key?(:roles) ? v.options[:roles] : nil }.compact.flatten.uniq
            if recipe_declared_roles.any? { |role| self.roles.keys.include?(role) } && !Dir["config/#{stage}/**/#{ns_name}"].empty?
              ns.send(:diff_config)
            end
          end
        end
      end
    end
  end

  define_config_compare_tasks(:deprec)
end