require 'ippon/form_data'

module Ippon
  module Roda
    module InstanceMethods
      def body_data
        @body_data ||= if request.content_type == "application/x-www-form-urlencoded"
          Ippon::FormData::URLEncoded.parse(request.body.read)
        else
          Ippon::FormData::URLEncoded.new
        end
      end
    
      def query_data
        @query_data ||= Ippon::FormData::URLEncoded.parse(request.query_string)
      end
    
      def form_data
        request.get? ? query_data : body_data
      end
    end
  end
end