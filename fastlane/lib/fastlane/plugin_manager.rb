module Fastlane
  class PluginManager
    PLUGINSFILE_NAME = "Plugins".freeze
    DEFAULT_GEMFILE_PATH = "Gemfile".freeze
    GEMFILE_SOURCE_LINE = "source \"https://rubygems.org\"\n"

    def gemfile_path
      # This is pretty important, since we don't know what kind of
      # Gemfile the user has (e.g. Gemfile, gems.rb, or custom env variable)
      Bundler::SharedHelpers.default_gemfile.to_s
    rescue Bundler::GemfileNotFound
      nil
    end

    def pluginsfile_path
      File.join(FastlaneFolder.path, PLUGINSFILE_NAME) if FastlaneFolder.path
    end

    def gemfile_content
      File.read(gemfile_path) if gemfile_path && File.exist?(gemfile_path)
    end

    def pluginsfile_content
      File.read(pluginsfile_path) if pluginsfile_path && File.exist?(pluginsfile_path)
    end

    def add_dependency(plugin_name)
      plugin_name = 'fastlane_' + plugin_name unless plugin_name.start_with?('fastlane_')

      unless (pluginsfile_content || "").include?(plugin_name)
        content = pluginsfile_content || "# Autogenerated by fastlane\n\n"
        content += "gem '#{plugin_name}'\n"
        File.write(pluginsfile_path, content)
        UI.success("Plugin '#{plugin_name}' was added.")
      end

      # We do this *after* creating the Plugin file
      # Since `bundle exec` would be broken if something fails on the way
      ensure_plugins_attached!

      true
    end

    # Makes sure, the user's Gemfile actually loads the Plugins file
    def plugins_attached?
      gemfile_path && gemfile_content.include?(code_to_attach)
    end

    def ensure_plugins_attached!
      return true if plugins_attached?
      UI.important("It looks like fastlane plugins are not yet set up for this project.")

      path_to_gemfile = gemfile_path || DEFAULT_GEMFILE_PATH

      if gemfile_content.to_s.length > 0
        UI.important("fastlane will modify your existing Gemfile at path '#{path_to_gemfile}'")
      else
        UI.important("fastlane will create a new Gemfile at path '#{path_to_gemfile}'")
      end

      UI.important("This change is neccessary for fastlane plugins to work")

      if UI.confirm("Can fastlane modify the Gemfile at path '#{path_to_gemfile}' for you?")
        attach_plugins!(path_to_gemfile)
        UI.success("Successfully modified '#{path_to_gemfile}'")
      else
        UI.important("Please add the following code to '#{path_to_gemfile}':")
        puts ""
        puts code_to_attach.magenta # we use puts to make it easier to copy and paste
        UI.user_error!("Please update '#{path_to_gemfile} and run fastlane again")
      end
      return true
    end

    def create_gemfile(path)
      File.write(DEFAULT_GEMFILE_PATH, default_gemfile_content)
    end

    # The code required to load the Plugins file
    def code_to_attach
      "plugins_path = File.join(File.dirname(__FILE__), 'fastlane', '#{PLUGINSFILE_NAME}')\n" \
      "eval(File.read(plugins_path), binding) if File.exist?(plugins_path)"
    end

    # Modify the user's Gemfile to load the plugins
    def attach_plugins!(path_to_gemfile)
      content = gemfile_content || GEMFILE_SOURCE_LINE
      content += "\ngem 'fastlane'\n" unless content.include?("gem 'fastlane'")
      # TODO: remove this after we're done debugging
      content += "gem 'pry'\n" unless content.include?("gem 'pry'")
      content += "\n#{code_to_attach}\n"
      File.write(path_to_gemfile, content)
    end

    # Warning: This will exec out
    # This is necessary since the user might be prompted for their password
    def install_dependencies!
      UI.message("Installing plugin dependencies...")
      ensure_plugins_attached!
      with_clean_bundler_env { exec("bundle install --quiet") }
    end

    # Warning: This will exec out
    # This is necessary since the user might be prompted for their password
    def update_dependencies!
      UI.message("Updating plugin dependencies...")
      ensure_plugins_attached!
      with_clean_bundler_env { exec("bundle update --quiet") }
    end

    def with_clean_bundler_env
      # There is an interesting problem with using exec to call back into Bundler
      # The `bundle ________` command that we exec, inherits all of the Bundler
      # state we'd already built up during this run. That was causing the command
      # to fail, telling us to install the Gem we'd just introduced, even though
      # that is exactly what we are trying to do!
      #
      # Bundler.with_clean_env solves this problem by resetting Bundler state before the
      # exec'd call gets merged into this process.
      Bundler.with_clean_env do
        yield if block_given?
      end
    end
  end
end
