module Dimples
  class Site
    attr_accessor :source_paths
    attr_accessor :output_paths
    attr_accessor :config
    attr_accessor :templates
    attr_accessor :categories
    attr_accessor :archives
    attr_accessor :pages
    attr_accessor :posts
    attr_accessor :latest_post
    attr_accessor :page_class
    attr_accessor :post_class

    def initialize(config)
      @source_paths = {}
      @output_paths = {}
      @templates = {}
      @categories = {}
      @archives = { year: {}, month: {}, day: {} }

      @pages = []
      @posts = []

      @latest_post = false

      @config = config

      @page_class = @config.class_override(:page) || Dimples::Page
      @post_class = @config.class_override(:post) || Dimples::Post

      @source_paths[:root] = File.expand_path(@config['source_path'])
      @output_paths[:site] = File.expand_path(@config['destination_path'])

      %w(pages posts public templates).each do |path|
        @source_paths[path.to_sym] = File.join(@source_paths[:root], path)
      end

      %w(archives posts categories).each do |path|
        output_path = File.join(@output_paths[:site], @config['paths'][path])
        @output_paths[path.to_sym] = output_path
      end
    end

    def generate
      prepare_output_directory
      scan_files
      generate_files
      copy_assets
    rescue Errors::RenderingError, Errors::PublishingError, Errors::GenerationError => e
      Dimples.logger.error("Failed to generate the site: #{e.message}.")
    end

    private

    def prepare_output_directory
      if Dir.exist?(@output_paths[:site])
        FileUtils.remove_dir(@output_paths[:site])
      end

      Dir.mkdir(@output_paths[:site])
    rescue => e
      error_message = "Couldn't prepare the output directory"
      error_message << " (#{e.message})" if @config['verbose_logging']

      raise Errors::GenerationError(error_message)
    end

    def scan_files
      scan_templates
      scan_pages
      scan_posts
    end

    def scan_templates
      Dir.glob(File.join(@source_paths[:templates], '**', '*.*')).each do |path|
        template = Dimples::Template.new(self, path)
        @templates[template.slug] = template
      end
    end

    def scan_pages
      Dir.glob(File.join(@source_paths[:pages], '**', '*.*')).each do |path|
        page = @page_class.new(self, path)
        @pages << page
      end
    end

    def scan_posts
      Dir.glob(File.join(@source_paths[:posts], '*.*')).reverse_each do |path|
        post = @post_class.new(self, path)

        next if post.draft

        post.categories.each do |slug|
          unless @categories[slug]
            name = @config['category_names'][slug] || slug.capitalize
            @categories[slug] = Dimples::Category.new(name, slug)
          end

          @categories[slug].posts << post
        end

        archive_year(post.year) << post
        archive_month(post.year, post.month) << post
        archive_day(post.year, post.month, post.day) << post

        @posts << post
      end

      @posts.each_index do |index|
        if index - 1 >= 0
          @posts[index].next_post = @posts.fetch(index - 1, nil)
        end

        if index + 1 < @posts.count
          @posts[index].previous_post = @posts.fetch(index + 1, nil)
        end
      end

      @latest_post = @posts.first
    end

    def archive_year(year)
      @archives[:year][year] ||= []
    end

    def archive_month(year, month)
      @archives[:month]["#{year}/#{month}"] ||= []
    end

    def archive_day(year, month, day)
      @archives[:day]["#{year}/#{month}/#{day}"] ||= []
    end

    def generate_files
      generate_posts
      generate_pages
      generate_archives

      generate_categories if @config['generation']['categories']
      generate_posts_feed if @config['generation']['feed']
      generate_category_feeds if @config['generation']['category_feeds']
    end

    def generate_posts
      Dimples.logger.debug_generation('posts', @posts.length) if @config['verbose_logging']

      @posts.each do |post|
        generate_post(post)
      end

      if @config['generation']['paginated_posts']
        paths = [@output_paths[:archives]]
        layout = @config['layouts']['posts']

        paginate(posts: @posts, paths: paths, layout: layout)
      end
    end

    def generate_post(post)
      post.write(post.output_path(@output_paths[:posts]))
    end

    def generate_pages
      Dimples.logger.debug_generation('pages', @pages.length) if @config['verbose_logging']

      @pages.each do |page|
        generate_page(page)
      end
    end

    def generate_page(page)
      page.write(page.output_path(@output_paths[:site]))
    end

    def generate_categories
      Dimples.logger.debug_generation('category pages', @categories.length) if @config['verbose_logging']

      @categories.each_value do |category|
        generate_category(category)
      end
    end

    def generate_category(category)
      paths = [@output_paths[:categories], category.slug]
      layout = @config['layouts']['category']
      context = { category: category.slug }

      paginate(posts: category.posts, title: category.name, paths: paths, layout: layout, context: context)
    end

    def generate_archives
      %w(year month day).each do |date_type|
        if @config['generation']["#{date_type}_archives"]
          date_type_sym = date_type.to_sym

          if @config['verbose_logging']
            Dimples.logger.debug_generation("#{date_type} archives", @archives[date_type_sym].count)
          end

          layout = @config['layouts']["#{date_type}_archives"]

          @archives[date_type_sym].each_value do |posts|
            title = posts[0].date.strftime(@config['date_formats'][date_type])
            paths = [@output_paths[:archives], posts[0].year]
            dates = { year: posts[0].year }

            case date_type
            when 'month'
              paths << posts[0].month
              dates[:month] = posts[0].month
            when 'day'
              paths.concat([posts[0].month, posts[0].day])
              dates.merge(month: posts[0].month, day: posts[0].day)
            end

            paginate(posts: posts, title: title, paths: paths, layout: layout, context: dates)
          end
        end
      end
    end

    def generate_feed(path, options)
      feed = @page_class.new(self)

      feed.filename = 'feed'
      feed.extension = @config['file_extensions']['feeds']
      feed.layout = 'feed'

      feed.write(feed.output_path(path), options)
    end

    def generate_posts_feed
      posts = @posts[0..@config['pagination']['per_page'] - 1]
      generate_feed(@output_paths[:site], posts: posts)
    end

    def generate_category_feeds
      @categories.each_value do |category|
        path = File.join(@output_paths[:categories], category.slug)
        posts = category.posts[0..@config['pagination']['per_page'] - 1]

        generate_feed(path, posts: category.posts, category: category.slug)
      end
    end

    def copy_assets
      if Dir.exist?(@source_paths[:public])
        Dimples.logger.debug("Copying assets...") if @config['verbose_logging']

        path = File.join(@source_paths[:public], '.')
        FileUtils.cp_r(path, @output_paths[:site])
      end
    rescue => e
      error_message = "Site assets failed to copy"
      error_message << " (#{e.message})" if @config['verbose_logging']

      raise Errors::GenerationError.new(error_message)
    end

    def paginate(posts:, title: nil, paths:, layout: false, context: {})
      raise "'#{layout}' template not found" unless @templates.key?(layout)

      per_page = @config['pagination']['per_page']
      page_count = (posts.length.to_f / per_page.to_i).ceil

      page_path = paths[0].gsub(@output_paths[:site], '') + '/'
      page_path += paths[1..-1].join('/') + '/' if paths.length > 1

      (1..page_count).each do |index|
        page = @page_class.new(self)

        page.layout = layout
        page.title = title || @templates[layout].title

        pagination = build_pagination(index, page_count, posts.count, page_path)
        output_path = File.join(paths, index != 1 ? "page#{index}" : '')

        context[:posts] = posts.slice((index - 1) * per_page, per_page)
        context[:pagination] = pagination

        page.write(page.output_path(output_path), context)
      end
    end

    def build_pagination(index, page_count, item_count, path)
      pagination = {
        page: index,
        pages: page_count,
        post_count: item_count,
        path: path
      }

      if (pagination[:page] - 1) > 0
        pagination[:previous_page] = pagination[:page] - 1
      end

      if (pagination[:page] + 1) <= pagination[:pages]
        pagination[:next_page] = pagination[:page] + 1
      end

      if pagination[:previous_page]
        pagination[:previous_page_url] = pagination[:path]

        if pagination[:previous_page] != 1
          page_string = "page#{pagination[:previous_page]}"
          pagination[:previous_page_url] += page_string
        end
      end

      if pagination[:next_page]
        page_string = "#{pagination[:path]}page#{pagination[:next_page]}"
        pagination[:next_page_url] = page_string
      end

      pagination
    end
  end
end
