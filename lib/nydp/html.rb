require "haml"
require "redcloth"
require "nydp"
require "nydp/literal"
require "nydp/builtin"
require "nydp/haml_parser"
require "nydp/plugin"
require "nydp/html/version"

module Nydp
  module Html
    class Plugin
      include Nydp::PluginHelper

      def name ; "Nydp/HTML plugin" ; end

      def base_path ; relative_path "../lisp/" ; end

      def load_rake_tasks ; end

      def loadfiles
        file_readers Dir.glob(relative_path '../lisp/html-*.nydp').sort
      end

      def testfiles
        file_readers Dir.glob(relative_path '../lisp/tests/**/*.nydp').sort
      end

      def setup ns
        ns.assign(:"textile-to-html" , Nydp::Html::TextileToHtml.instance)
        ns.assign(:"haml-to-html"    , Nydp::Html::HamlToHtml.instance   )
        ns.assign(:"percent-encode"  , Nydp::Html::PercentEncode.instance)
      end
    end

    class PercentEncode
      include Nydp::Builtin::Base, Singleton

      def builtin_call arg
        percent_encode arg.to_s
      end

      def percent_encode s
        s.gsub('%', '%25').gsub(/[ \n"\!\#\$\'\(\)\*\+\,:;=@\&\?.<>\\^`{\|}~\[\]\/]/) { |x| "%%%2X" % x.ord }
      end
    end

    #
    # =============================
    # this is a set of hacks to re-create the old #suppress_eval behaviour
    #
    #

    # generator ignores all dynamic (code) elements
    class HamlNoDynamicGenerator < Temple::Generators::StringBuffer
      def on_dynamic(code)
        # no-op, we don't want to allow any ruby evaluation here
      end
    end

    # engine excludes dynamic merger, and uses our own parser which is a copy of haml 7.5.1, with all ruby evaluation hacked out
    class HamlNoDynamicEngine < Haml::Engine
      remove Haml::Parser
      remove Haml::DynamicMerger
      prepend Nydp::HamlParser
    end

    # copy of Haml::Template, just using our own hacked engine instead of base haml engine
    HamlNoDynamicTemplate = Temple::Templates::Tilt.create(
      HamlNoDynamicEngine,
      register_as: [:haml, :haml],
    )

    #
    # this is the end of the hacks to re-create the old #suppress_eval behaviour
    # see also: haml_parser.rb in this folder
    # =============================
    #

    class HamlToHtml
      include Nydp::Builtin::Base, Singleton
      def normalise_indentation txt
        lines = txt.split(/\n/).select { |line| line.strip != "" }
        return txt if lines.length == 0
        indentation = /^ +/.match(lines.first)
        return txt unless indentation
        indentation = indentation.to_s
        txt.gsub(/^#{indentation}/, "")
      end

      def convert_from_haml convertible
        HamlNoDynamicTemplate.new(generator: HamlNoDynamicGenerator) { normalise_indentation(convertible) }.render
      rescue Exception => e
        if e.line
          lines = convertible.split(/\n/)
          beginning = e.line - 2
          beginning = 0 if beginning < 0
          selection = lines[beginning...(e.line + 1)].join "\n"
          "#{e.message}<br/>line #{e.line}<br/><br/><pre>#{selection}</pre>"
        else
          e.message
        end
      end

      def builtin_call *args
        convert_from_haml(args.first.to_s)
      end
    end

    class TextileToHtml
      include Nydp::Builtin::Base, Singleton
      def builtin_call *args
        src = args.first.to_s
        rc = RedCloth.new(src)
        rc.no_span_caps = true
        rc.to_html
      end
    end
  end
end

Nydp.plug_in Nydp::Html::Plugin.new
