module Salt
  class Page
    include Frontable
    include Publishable

    attr_accessor :path
    attr_accessor :title
    attr_accessor :contents
    attr_accessor :filename
    attr_accessor :extension
    attr_accessor :layout

    def initialize(site, path = nil)
      @site = site
      
      if path
        @path = path
        @contents = read_with_yaml(path)
        @filename = File.basename(path, File.extname(path))
      else
        @filename = 'index'
      end

      @extension = @site.config['file_extensions']['pages']
      @layout ||= @site.config['layouts']['page']
    end

    def type
      :page
    end

    def output_path(parent_path)
      return parent_path if @path.nil?
      File.join(parent_path, File.dirname(@path).gsub(@site.source_paths[:pages], ''))
    end
  end
end