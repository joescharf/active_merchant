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

      cattr_accessor :pem_file
      attr_reader :options, :response, :req_xml, :res_xml, :res_hsh

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
      ########################################################################
      def initialize(options = {})
        requires!(options, :applogin, :conntkt)        

        @options = {
          :pem => QuickbooksMerchantServiceGateway.pem_file
          }.update(options)

        raise ArgumentError, "You need to pass in your pem file using the :pem parameter or set it globally using ActiveMerchant::Billing::QuickbooksMerchantServiceGateway.pem_file = File.read( File.dirname(__FILE__) + '/../mycert.pem' ) or similar" if @options[:pem].blank?

        # Set the gateway mode, default to test.
        Base.gateway_mode = @options[:gw_mode].to_sym ||= :test
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
      # 0. SESSION_TICKET:
      # Authorize a credit card for later capture
      ########################################################################
      def session_ticket(options = {})
        xml = signon_app_cert_rq
        response = commit('session_ticket', xml)
      end
      
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
        response = session_ticket
        if response.success?
          options[:session_ticket] = response.authorization
          options[:order_id] ||= generate_unique_id
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
        data = ssl_post(url, xml, headers)
        
        response = parse(action, data)
        message  = message_from(response)
        
        # Post Processing - Create the Response object
        case action
          
        when 'session_ticket'
          @response = Response.new(success?(response), message, response, 
                       :test => test?,
                       :authorization => response[:session_ticket]
                       )
        else
          @response = Response.new(success?(response), message, response, 
                       :test => test?,
                       :authorization => response[:transaction_id],
                       :cvv_result => cvv_result(response),
                       :avs_result => avs_result(response)
                       )        
        end
      end
      
      # Parse the XML returned from the commit and set the applicable result variables
      def parse(action, data)
        h = recursively_symbolize_keys(Hash.from_xml(data))
        results = {}

        case action
        when 'session_ticket'
          if results[:raw]  = h[:qbmsxml][:signon_msgs_rs][:signon_app_cert_rs]
            results[:session_ticket]            = results[:raw][:session_ticket]
          end
          
        when 'authonly'
          if results[:raw]  = h[:customer_credit_card_auth_rs]
            results[:transaction_id]           = results[:raw][:credit_card_trans_id]
            results[:authorization_code]       = results[:raw][:authorization_code]
            results[:card_code]                = results[:raw][:card_security_code_match]
          end
        
        when 'capture'
          if results[:raw]  = h[:customer_credit_card_capture_rs]
            results[:transaction_id]           = results[:raw][:credit_card_trans_id]
            results[:authorization_code]       = results[:raw][:authorization_code]
          end

        when 'purchase'
          if results[:raw]  = h[:qbmsxml][:qbmsxml_msgs_rs][:customer_credit_card_charge_rs]
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
      
      # Determine if transaction was successful based on :response_code
      def success?(response)
        response[:response_code] == 0
      end
      
      # Assign the CVV Result code
      def cvv_result(response)
        case response[:raw][:card_security_code_match]
        when "Pass"
          return "M" # Match
        else
          return "P" # Not Processed
        end
      end
      
      # Assign the AVS Result code
      def avs_result(response)
        attrs={}
        # Check the Street Address:
        case response[:raw][:avs_street]
        when "Pass"
          attrs[:street_match] = 'Y'
        else
          attrs[:street_match] = nil
        end        
        
        # Check the Postal Code:
        case response[:raw][:avs_zip]
        when "Pass"
          attrs[:postal_match] = 'Y'
        else
          attrs[:postal_match] = nil
        end        
      end
      
      # Decode and create status messages from the results of the commit
      def message_from(response)
        case response[:response_code]
        when 0
          return "OK"
        when 2000
          return "ERROR 2000: Invalid Connection Ticket"
        when 10303
          return "ERROR 10303: TransRequestID is empty"
        when 10305
          return "ERROR 10305: An error occurred when validating the supplied payment data"
        when 10309
          return "ERROR 10309: The credit card number is formatted incorrectly"
        when 10312
          return "ERROR 10312: The credit card Transaction ID was not found"
        when 10409
          return CVVResult.messages[ response[:card_code] ] if CARD_CODE_ERRORS.include?(response[:card_code])
        end
      end
      
      def recursively_symbolize_keys(hash)
        return unless hash.is_a?(Hash)

        hash.symbolize_keys!
        hash.each{|k,v| recursively_symbolize_keys(v)}
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

