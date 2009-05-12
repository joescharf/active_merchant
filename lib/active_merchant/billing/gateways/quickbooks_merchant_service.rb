include Builder

module ActiveMerchant #:nodoc:
  module Billing #:nodoc:

    class CVVResult
      MESSAGES = {
        'PASS'         => 'Match',
        'FAIL'         => 'No Match',
        'NOTAVAILABLE' => 'Card does not support verification'
      }
    end
    

    class QuickbooksMerchantServiceGateway < Gateway

      API_VERSION = '3.0'

      class_inheritable_accessor :test_url, :production_url, :debug_url

      cattr_accessor :certificate
      attr_reader :options, :req_xml, :res_xml, :res_hsh, :result

      # Setup some class variables:
      self.debug_url = 'https://webmerchantaccount.quickbooks.com/j/diag/http'
      self.test_url = 'https://webmerchantaccount.ptc.quickbooks.com/j/AppGateway'
      self.production_url = 'https://webmerchantaccount.quickbooks.com/j/AppGateway'
      
      self.ssl_strict = false # We don't have certs to verify this gateway
      self.money_format = :dollars
      self.supported_countries = ['US']
      self.supported_cardtypes = [:visa, :master, :american_express, :discover]
      self.homepage_url = 'http://developer.intuit.com/'
      self.display_name = 'Quickbooks Merchant Service'
      
      #########################################################################
      # INITIALIZE
      # Initialize the object
      #  ==== Options
      # * <tt>:pem</tt> -- Client certificate with CN = hostname:applogin (REQ)
      # * <tt>:applogin</tt> -- Application login defined at appreg.intuit.com (REQ)
      # * <tt>:conntkt</tt> -- Connection ticket for registered application (REQ)
      # * <tt>:gw_mode</tt> -- :test, :debug, :production (need the symbol!)
      # * <tt>:transaction_log_callback -- Model object for txn logging
      # * <tt>:transaction_log_logger_callback -- logger object for txn logging
      # * <tt>:test_mode_error</tt> -- Error to force if gw_mode == :test
      ########################################################################
      def initialize(options = {})
        requires!(options, :pem, :applogin, :conntkt)        
        @options = options

        # Set the gateway mode, default to test.
        Base.gateway_mode = @options[:gw_mode] ||= :test
        super
      end
      
      def debug?
        Base.gateway_mode == :debug
      end
      
      def production?
        Base.gateway_mode == :production
      end
      
      
      def get_post_url
        case Base::gateway_mode
        when :production
          post_url = self.production_url
        when :debug
          post_url = self.debug_url
        else
          post_url = self.test_url
        end
        post_url
      end      
            
      #########################################################################
      # QBMS_CREATE_HOSTED_SESSION_TICKET_REQUEST 
      # Create session ticket for a hosted application
      #
      # Requires:
      # @options[:applogin]
      # @options[:conntkt]
      #
      # Returns:
      # xml: xml-builder XML object
      ########################################################################
      def signon_app_cert_rq()
        xml = Builder::XmlMarkup.new(:indent => 2)
        create_xml_header(xml, options)

        xml.tag!('QBMSXML') do
          xml.tag!('SignonMsgsRq') do
            xml.tag!('SignonAppCertRq') do
              xml.tag!('ClientDateTime', Time.now)
              xml.tag!('ApplicationLogin', @options[:applogin])
              xml.tag!('ConnectionTicket', @options[:conntkt])
            end
          end
        end
        xml.target!
      end

      #########################################################################
      # CUSTOMER_CREDIT_CARD_AUTH_RQ
      # Create credit card authorization request to post to QBMS
      #
      # Requires:
      # amount, creditcard
      # options[:session_ticket]
      # options[:order_id]
      # options[:address]{:name, :address, :zip}
      #
      # Returns:
      # xml: xml-builder XML object
      ########################################################################
      def customer_credit_card_auth_rq(amount, creditcard, options)
        xml = Builder::XmlMarkup.new(:indent => 2)

        create_qbmsxml_msgs_rq(xml,options) {
          xml.tag!('CustomerCreditCardAuthRq') do
            xml.tag!('TransRequestID', options[:order_id])
            add_creditcard(xml, creditcard)        
            xml.tag!('Amount', amount)
            add_address(xml, options)   
            add_creditcard_security_code(xml, creditcard)
          end
        }

        xml.target!
      end

      #########################################################################
      # CUSTOMER_CREDIT_CARD_CAPTURE_RQ
      # Create credit card authorization request to post to QBMS
      #
      # Returns:
      # xml: xml-builder XML object
      ########################################################################
      def customer_credit_card_capture_rq(amount, authorization, options)
        xml = Builder::XmlMarkup.new(:indent => 2)
        
        create_qbmsxml_msgs_rq(xml,options) {
          xml.tag!('CustomerCreditCardCaptureRq') do
            xml.tag!('TransRequestID', options[:order_id])
            xml.tag!('CreditCardTransID', authorization)
            xml.tag!('Amount', amount)
          end
        }
        
        xml.target!
      end

      
      #########################################################################
      # QBMS_CREATE_CC_CHARGE_REQUEST
      # Create credit card request to post to QBMS
      #
      # Returns:
      # xml: xml-builder XML object
      ########################################################################
      def customer_credit_card_charge_rq(amount, creditcard, options)
        xml = Builder::XmlMarkup.new(:indent => 2)

        create_qbmsxml_msgs_rq(xml,options) {
          xml.tag!('CustomerCreditCardChargeRq') do
            xml.tag!('TransRequestID', options[:order_id])
            add_creditcard(xml, creditcard)        
            xml.tag!('Amount', amount)
            add_address(xml, options)   
            add_creditcard_security_code(xml, creditcard)
          end
        }

        xml.target!
      end

      #########################################################################
      # QBMS_CREATE_VOID_OR_REFUND_REQUEST
      # Create credit card void request to post to QBMS
      #
      # Returns:
      # xml: xml-builder XML object
      ########################################################################
      def customer_credit_card_txn_void_or_refund_rq(authorization, options)
        xml = Builder::XmlMarkup.new(:indent => 2)

        create_qbmsxml_msgs_rq(xml,options) {
            xml.tag!('CustomerCreditCardTxnVoidOrRefundRq') do
              xml.tag!('TransRequestID', options[:order_id])
              xml.tag!('CreditCardTransID', authorization)
              xml.tag!('Amount', options[:amount])
           end
         }
         
        xml.target!
      end
      
      #### START PROCESSING ACTION METHODS ####
      
      #########################################################################
      # 1. AUTHORIZE:
      # Authorize a credit card for later capture
      ########################################################################
      def authorize(amount, creditcard, options = {})
        xml = signon_app_cert_rq
        response = commit('session_ticket', xml)
        if response.success?
          options[:session_ticket] = response.authorization
          xml = customer_credit_card_auth_rq(amount, creditcard, options)
          commit('authonly', xml)
        end
      end
      
      #########################################################################
      # 2. CAPTURE:
      # Capture and process a previously authorized transaction
      ########################################################################
      def capture(amount, authorization, options = {})
        xml = signon_app_cert_rq
        response = commit('session_ticket', xml)
        if response.success?
          options[:session_ticket] = response.authorization
          xml = customer_credit_card_capture_rq(amount, authorization, options)
          commit('capture', xml)
        end
      end
      
      
      #########################################################################
      # 3. PURCHASE: 
      # Initiate a credit card purchase request to QBMS (Auth + Capture)
      #
      # Returns (from commit):
      # lxml: libxml-ruby object
      ########################################################################
      def purchase(amount, creditcard, options = {})
        xml = signon_app_cert_rq
        response = commit('session_ticket', xml)
        if response.success?
          options[:session_ticket] = response.authorization
          xml = customer_credit_card_charge_rq(amount, creditcard, options)
          commit('purchase', xml)
        end
        
      end                       

      #########################################################################
      # 4. VOID
      # Void a previously processed transaction
      ########################################################################
      def void(authorization, options = {})
        xml = signon_app_cert_rq
        response = commit('session_ticket', xml)
        if response.success?
          options[:session_ticket] = response.authorization
          xml = customer_credit_card_txn_void_or_refund_rq(authorization, options)
          commit('void', xml)
        end
      end

private
          
      #########################################################################
      # COMMIT:
      # Commit the transaction to server
      #
      # Returns:
      ########################################################################
      def commit(action, xml)
        headers = { 'Content-Type' => 'application/x-qbmsxml',
                    'Content-length' => xml.size.to_s }
                
        # Post to server
        url = get_post_url
        # puts "URL: " + url.to_s
        # puts "XML Req: " + xml.to_yaml
        data = ssl_post(url, xml, headers)
        # puts "DATA Resp: " + data.to_yaml
        
        response = parse(action, data)
        message  = message_from(response)
        
        # Transaction Logging - To Logger 
        log_callback(action, @options[:transaction_log_logger_callback], url, xml, data, response  )

        # Transaction Logging - To Database or other
        if @options[:transaction_log_callback]
          @options[:transaction_log_callback].send :create, {:action => url, :request => xml, :response => data, :parsed => response }
        end

        # Post Processing
        case action
          
        when 'session_ticket'
          Response.new(success?(response), message, response, 
                       :test => test?,
                       :authorization => response[:session_ticket]
                       )
        else
          Response.new(success?(response), message, response, 
                       :test => test?,
                       :authorization => response[:transaction_id],
                       :cvv_result => response[:card_code],
                       :avs_result => nil
                       )        
        end
      end
      
      # Determine if transaction was successful based on :response_code
      def success?(response)
        response[:response_code] == 0
      end
      
      # Decode and create status messages from the results of the commit
      def message_from(results)
        case results[:response_code]
        when 0
          return results[:response_reason_text]
        when 10305
          return "ERROR: An error occurred when validating the supplied payment data"
        when 10309
          return "ERROR: The credit card number is formatted incorrectly"
        when 10312
          return "ERROR: The credit card Transaction ID was not found"
        when 10409
          return CVVResult.messages[ results[:card_code] ] if CARD_CODE_ERRORS.include?(results[:card_code])
        end
      end

      # Parse the XML returned from the commit and set the applicable result variables
      def parse(action, data)
        h = (Hash.from_xml(data)).symbolize_keys
        results = {}
        case action
        when 'session_ticket'
          h = (h[:qbmsxml]['signon_msgs_rs']).symbolize_keys
          if results[:raw]  = h[:signon_app_cert_rs].symbolize_keys
            results[:session_ticket]            = results[:raw][:session_ticket]
          end
        when 'authonly'
          h = (h[:qbmsxml]['qbmsxml_msgs_rs']).symbolize_keys
          if results[:raw]  = h[:customer_credit_card_auth_rs].symbolize_keys
            results[:transaction_id]           = results[:raw][:credit_card_trans_id]
            results[:authorization_code]       = results[:raw][:authorization_code]
            results[:card_code]                = results[:raw][:card_security_code_match]
          end
        
        when 'capture'
          h = (h[:qbmsxml]['qbmsxml_msgs_rs']).symbolize_keys
          if results[:raw]  = h[:customer_credit_card_capture_rs].symbolize_keys
            results[:transaction_id]           = results[:raw][:credit_card_trans_id]
            results[:authorization_code]       = results[:raw][:authorization_code]
          end

        when 'purchase'
          h = (h[:qbmsxml]['qbmsxml_msgs_rs']).symbolize_keys
          if results[:raw]  = h[:customer_credit_card_charge_rs].symbolize_keys
            results[:transaction_id]           = results[:raw][:credit_card_trans_id]
            results[:authorization_code]       = results[:raw][:authorization_code]
          end

        when 'void'
          h = (h[:qbmsxml]['qbmsxml_msgs_rs']).symbolize_keys
          if results[:raw]  = h[:customer_credit_card_txn_void_or_refund_rs].symbolize_keys
            results[:transaction_id]           = results[:raw][:credit_card_trans_id]
            results[:void_type]                = results[:raw][:void_or_refund_txn_type]
          end
        end

        results[:response_code]             = results[:raw][:status_code].to_i
        results[:response_reason_code]      = results[:raw][:status_severity]
        results[:response_reason_text]      = results[:raw][:status_message]
      
        results
      end
      
      # Convert a hash from string representation to symbols with underscores
      def symbolize_hash(hsh)
        r = {}
        unless hsh.nil?
          hsh.each_pair do |k,v|
            r[k.underscore.to_sym] = v
          end 
        end
        r
      end
      
      # Populate the header and QBMSXML for a QBMSXMLMsgsRq Request
      def create_qbmsxml_msgs_rq(xml, options)
        create_xml_header(xml, options)

        xml.tag!('QBMSXML') do
          add_session_ticket(xml, options)
          xml.tag!('QBMSXMLMsgsRq') do
            yield
          end
        end
      end

      # Create the XML header for a QBMSXML Request
      def create_xml_header(xml,options)
        xml.instruct!(:xml, :version => '1.0', :encoding => 'utf-8')
        xml.instruct!(:qbmsxml, :version => API_VERSION)
      end 
      
      def add_session_ticket(xml, options)
        if options.has_key? :session_ticket
          xml.tag!('SignonMsgsRq') do
            xml.tag!('SignonTicketRq') do
              xml.tag!('ClientDateTime', Time.now)
              xml.tag!('SessionTicket', options[:session_ticket])
            end
          end   
        end     
      end                  
      
      def add_address(xml, options) 
        if address = options[:billing_address] || options[:address]     
          xml.tag!('NameOnCard', address[:name])
          xml.tag!('CreditCardAddress', address[:street1] || address[:address1])
          xml.tag!('CreditCardPostalCode', address[:zip].gsub!(/[-\s]/, ''))
        end
      end

      def add_invoice(xml, options)
      end
      
      def add_creditcard(xml, creditcard)
        xml.tag!('CreditCardNumber', creditcard.number)
        xml.tag!('ExpirationMonth', creditcard.month)
        xml.tag!('ExpirationYear', creditcard.year)      
      end

      def add_creditcard_security_code(xml, creditcard)
        xml.tag!('CardSecurityCode', creditcard.verification_value)
      end
      

      def log_callback(action, callback, url, req_xml, res_xml, res_hsh  )
        if callback            
          callback.send :info, "************************************************\n"
          callback.send :info, "**** #{Time.now} - Begin Action - #{action} ****\n"
          callback.send :info, "************************************************\n"
          callback.send :info, "**** URL:\n" + url
          callback.send :info, "**** Request:\n" + req_xml
          callback.send :info, "**** Response:\n" + res_xml
          callback.send :info, "**** Parsed Response:\n" + res_hsh.to_yaml
          callback.send :info, "************************************************\n"
          callback.send :info, "**** #{Time.now} - End Action - #{action} ******\n"
          callback.send :info, "************************************************\n\n"
        end  
      end
      
    end
  end
end

