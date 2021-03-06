namespace :gemcutter do
  namespace :index do
    desc "Update the index"
    task :update => :environment do
      require 'benchmark'
      Benchmark.bm do|b|
        b.report("update index") { Indexer.new.perform }
      end
    end
  end

  namespace :import do
    desc 'Bring the gems through the gemcutter process'
    task :process => :environment do
      gems = Dir[File.join(ARGV[1] || "#{Gem.path.first}/cache", "*.gem")].sort.reverse
      puts "Processing #{gems.size} gems..."
      gems.each do |path|
        puts "Processing #{path}"
        cutter = Pusher.new(nil, File.open(path))

        cutter.process
      end
    end
  end

  namespace :rubygems do
    desc "update rubygems. run as: rake gemcutter:rubygems:update VERSION=[version number] RAILS_ENV=[staging|production] S3_KEY=[key] S3_SECRET=[secret]"
    task :update => :environment do
      version     = ENV["VERSION"]
      app_path    = Rails.root.join("config", "application.rb")
      old_content = app_path.read
      new_content = old_content.gsub(/RUBYGEMS_VERSION = "(.*)"/, %{RUBYGEMS_VERSION = "#{version}"})

      app_path.open("w") do |file|
        file.write new_content
      end

      updater = Indexer.new
      html    = Nokogiri.parse(open("http://rubyforge.org/frs/?group_id=126"))
      links   = html.css("a[href*='#{version}']").map { |n| n["href"] }

      if links.empty?
        abort "gem/tgz/zip for RubyGems #{version} hasn't been uploaded yet!"
      else
        links.each do |link|
          url = "http://rubyforge.org#{link}"

          puts "Uploading #{url}..."
          updater.directory.files.create({
            :body   => open(url).read,
            :key    => "rubygems/#{File.basename(url)}",
            :public => true
          })
        end
      end
    end

    desc "Update the download counts for all gems."
    task :update_download_counts => :environment do
      case_query = Rubygem.pluck(:name)
        .map { |name| "WHEN '#{name}' THEN #{$redis["downloads:rubygem:#{name}"].to_i}" }
        .join("\n            ")

      ActiveRecord::Base.connection.execute <<-SQL.strip_heredoc
        UPDATE rubygems
          SET downloads = CASE name
            #{case_query}
          END
      SQL
    end
  end

  desc "Move all but the last 2 days of version history to SQL"
  task :migrate_history => :environment do
    Download.copy_all_to_sql do |t,c,v|
      puts "#{c} of #{t}: #{v.full_name}"
    end
  end
end
