require 'sequel_paperclip/geometry'
require 'sequel_paperclip/interpolations'

module Sequel
  module Plugins
    module Paperclip

      def self.configure(model, opts={})
      end

      module ClassMethods
        attr_accessor :attachments

        def attachment(name, options)
          attr_accessor name

          define_method("#{name}_url") do |style|
            Interpolations.interpolate(self.class.attachments[name][:url], self, name, style)
          end

          define_method("#{name}_path") do |style|
            Interpolations.interpolate(self.class.attachments[name][:path], self, name, style)
          end

          self.attachments ||= {}
          self.attachments[name] = options
        end
      end

      module InstanceMethods       
        def before_save
          self.class.attachments.each_pair do |attachment_name, attachment_options|
            filename = send("#{attachment_name}_file_name")
            if filename.blank?
              filename = ActiveSupport::SecureRandom.hex(4).to_s
              send("#{attachment_name}_file_name=", filename)
            end
          end
          super
        end
        
        def after_save
          self.class.attachments.each_pair do |attachment_name, attachment_options|
            source_geo = Geometry.from_file(send(attachment_name))
            attachment_options[:styles].each_pair do |style_name, style_options|
              fullpath = send("#{attachment_name}_path", style_name)
              FileUtils.mkdir_p(File.dirname(fullpath))

              target_geo = Geometry.from_s(style_options[:geometry])
              target_crop = (style_options[:geometry][-1,1]=="#")
              resize_str, crop_str = source_geo.transform(target_geo, target_crop)

              cmd = []
              cmd << "convert"
              cmd << "-resize"
              cmd << "'#{resize_str}'"
              if target_crop
                cmd << "-crop"
                cmd << "'#{crop_str}'"
              end
              cmd << send(attachment_name).path
              cmd << "#{style_options[:format]}:#{fullpath}"
              `#{cmd*" "}`
            end
          end
          super
        end

        def after_destroy
          self.class.attachments.each_pair do |attachment_name, attachment_options|
            attachment_options[:styles].each_pair do |style_name, style_options|
              fullpath = send("#{attachment_name}_path", style_name)
              begin
                FileUtils.rm(fullpath)
              rescue Errno::ENOENT => error
              end
            end
          end              
          super
        end
      end
    end
  end
end

