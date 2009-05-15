require File.dirname(__FILE__) + '/../../test_helper'

class QuickbooksMerchantServiceTest < ActionController::TestCase

  def setup
    @qbms = fixtures(:quickbooks_merchant_service)
    
    @gateway = QuickbooksMerchantServiceGateway.new( @qbms )

    @credit_card = credit_card
    @amount = "1.00"
    
    @address = address
    @options = {}
    
  end
  
  test "gateway mode test" do
    @gateway = QuickbooksMerchantServiceGateway.new(  :gw_mode  => :test,
                                                      :pem      => @qbms[:pem],
                                                      :applogin => @qbms[:applogin],
                                                      :conntkt  => @qbms[:conntkt]
                                                    )
    assert @gateway.test?
  end

  test "gateway mode debug" do
    @gateway = QuickbooksMerchantServiceGateway.new(  :gw_mode  => :debug,
                                                      :pem      => @qbms[:pem],
                                                      :applogin => @qbms[:applogin],
                                                      :conntkt  => @qbms[:conntkt]
                                                    )
    assert @gateway.debug?
  end

  test "gateway mode production" do
    @gateway = QuickbooksMerchantServiceGateway.new(  :gw_mode  => :production,
                                                      :pem      => @qbms[:pem],
                                                      :applogin => @qbms[:applogin],
                                                      :conntkt  => @qbms[:conntkt]
                                                    )
    assert @gateway.production?
  end

  test "create session ticket" do
    session_ticket = @gateway.signon_app_cert_rq
    h = parse(session_ticket)
    assert_equal @qbms[:conntkt], h[:qbmsxml][:signon_msgs_rq][:signon_app_cert_rq][:connection_ticket]
    assert_equal @qbms[:applogin], h[:qbmsxml][:signon_msgs_rq][:signon_app_cert_rq][:application_login]
  end
  
  test "remote get session ticket" do
    response = @gateway.session_ticket
      
    # Test the Response object for OK status and status code = 0
    assert_not_nil @gateway.response
    assert @gateway.response.success?
    assert_equal "OK", @gateway.response.message
    assert_equal 0, @gateway.response.params['response_code']
    
    # Session ticket is stored in Response.authorization
    assert_not_nil @gateway.response.authorization
    assert_equal @gateway.response.authorization, @gateway.response.params['raw'][:session_ticket]  
  end
  
  test "remote get session ticket with invalid connection tkt should cause error response" do
    @invalid_gateway = QuickbooksMerchantServiceGateway.new( @qbms.update(:conntkt => 'Invalid Conn Tkt') )
    response = @invalid_gateway.session_ticket
      
    assert !@invalid_gateway.response.success?
    assert_equal 2000, @invalid_gateway.response.params['response_code']
    assert_equal "ERROR 2000: Invalid Connection Ticket", @invalid_gateway.response.message
  end

  #############################################################################
  # PURCHASE TESTS
  #############################################################################
  
  test "create purchase request" do
    # For this test, it doesn't matter what the session ticket is, but we need
    # one, nonetheless
    @options[:session_ticket] = "ABCD1234"
    ccreq = @gateway.customer_credit_card_charge_rq(@amount, @credit_card, @options)
    h = parse(ccreq)
    
    assert_not_nil h
    assert_equal @credit_card.number, h[:qbmsxml][:qbmsxml_msgs_rq][:customer_credit_card_charge_rq][:credit_card_number]
  end

  
  test "remote create valid purchase" do
    @gateway.purchase(@amount, @credit_card, @options)

    assert @gateway.response.success?
    assert_equal "OK", @gateway.response.message
  
    # Check the CVV Result - M indicates Match
    assert_equal "M", @gateway.response.cvv_result['code']
  end
  
  # test "create declined transaction" do
  #   @gateway = QuickbooksMerchantServiceGateway.new(  :pem => @cert,
  #                                                     :gw_mode => :test,
  #                                                     :applogin => QBMS[:test_gw][:applogin],
  #                                                     :conntkt => QBMS[:test_gw][:conntkt],
  #                                                     :test_mode_error => "configid=10401_decline" # Card Declined
  #                                                   )
  #   @gateway.purchase(@amount, @credit_card, @options)
  # 
  #   assert_equal "ERROR", @gateway.result[:status_severity]
  #   assert_equal 10401, @gateway.result[:status_code]
  # end
  # 
  # test "create cvv declined transaction" do
  #   @gateway = QuickbooksMerchantServiceGateway.new(  :pem => @cert,
  #                                                     :gw_mode => :test,
  #                                                     :applogin => QBMS[:test_gw][:applogin],
  #                                                     :conntkt => QBMS[:test_gw][:conntkt],
  #                                                     :test_mode_error => "configid=10000_avscvdfail" # CVD FAIL
  #                                                   )
  #   @gateway.purchase(@amount, @credit_card, @options)
  # 
  #   assert_equal "WARN", @gateway.result[:status_severity]
  #   assert_equal 10100, @gateway.result[:status_code]
  # end
  # 
  # 
  # test "create valid purchase no session ticket" do
  #   ccreq = @gateway.customer_credit_card_charge_rq(@amount, @credit_card, @options)
  #   @gateway.commit('sale', ccreq)
  # 
  #   assert_equal "ERROR", @gateway.result[:status_severity]
  #   assert_equal 2000, @gateway.result[:status_code]
  #   assert_equal "Invalid signon", @gateway.result[:status_message]
  # end
  # 
  # test "create purchase invalid credit card" do
  #   @credit_card.number = "1234567890123456"
  #   @gateway.purchase(@amount, @credit_card, @options)
  # 
  #   assert_equal "ERROR", @gateway.result[:status_severity]
  #   assert_equal 10301, @gateway.result[:status_code]
  #   assert_equal "This credit card number is invalid.", @gateway.result[:status_message]
  # 
  # end
  # 
  # test "create purchase expired credit card" do
  #   @credit_card.year = Time.now.year - 1
  #   @gateway.purchase(@amount, @credit_card, @options)
  # 
  #   assert_equal "ERROR", @gateway.result[:status_severity]
  #   assert_equal 10302, @gateway.result[:status_code]
  #   assert_equal "An error occurred while validating the date value #{Time.now.month}/#{Time.now.year - 1} in the field ExpirationMonth/ExpirationYear.", @gateway.result[:status_message]
  # 
  # end
  # 
  # test "create purchase with negative amount" do
  #   @amount = -1
  #   @gateway.purchase(@amount, @credit_card, @options)
  # 
  #   assert_equal "ERROR", @gateway.result[:status_severity]
  #   assert_equal 10300, @gateway.result[:status_code]
  #   assert_equal "An error occurred while converting the amount #{@amount} in the field Amount.", @gateway.result[:status_message]
  # 
  # end
  # 
  # test "create purchase with zero amount" do
  #   @amount = 0
  #   @gateway.purchase(@amount, @credit_card, @options)
  # 
  #   assert_equal "ERROR", @gateway.result[:status_severity]
  #   assert_equal 10300, @gateway.result[:status_code]
  #   assert_equal "An error occurred while converting the amount #{@amount} in the field Amount.", @gateway.result[:status_message]
  # 
  # end
  # 
  # test "create purchase with very large amount" do
  #   @amount = 1000000000000
  #   @gateway.purchase(@amount, @credit_card, @options)
  # 
  #   assert_equal "ERROR", @gateway.result[:status_severity]
  #   assert_equal 10300, @gateway.result[:status_code]
  #   assert_equal "An error occurred while converting the amount #{@amount} in the field Amount.", @gateway.result[:status_message]
  # 
  # end
  # 
  # test "create purchase with integer amount" do
  #   @amount = 10
  #   @gateway.purchase(@amount, @credit_card, @options)
  # 
  #   assert_equal "INFO", @gateway.result[:status_severity]
  #   assert_equal 0, @gateway.result[:status_code]
  # end
  # 
  # test "create purchase with long address" do
  #   # Tests address > 30 chars (QBMS limitation)
  #   @options[:address][:address] = "1234 Really Long Street, Apartment 1234567890 South West"
  #   @gateway.purchase(@amount, @credit_card, @options)
  # 
  #   assert_equal "ERROR", @gateway.result[:status_severity]
  #   assert_equal 10304, @gateway.result[:status_code]
  #   assert_equal "The string #{@options[:address][:address]} in the field CreditCardAddress is too long. The maximum length is 30.", @gateway.result[:status_message]
  # 
  # end
  # 
  # test "create purchase with no zip" do
  #   @options[:address][:zip] = ""
  #   @gateway.purchase(@amount, @credit_card, @options)
  # 
  #   assert_equal "INFO", @gateway.result[:status_severity]
  #   assert_equal 0, @gateway.result[:status_code]
  # 
  # end
  # 
  # test "create purchase with invalid zip" do
  #   @options[:address][:zip] = "123"
  #   @gateway.purchase(@amount, @credit_card, @options)
  # 
  #   assert_equal "INFO", @gateway.result[:status_severity]
  #   assert_equal 0, @gateway.result[:status_code]
  # 
  # end
  # 
  # test "create purchase with invalid and long zip" do
  #   @options[:address][:zip] = "123456789012345"
  #   @gateway.purchase(@amount, @credit_card, @options)
  # 
  #   assert_equal "ERROR", @gateway.result[:status_severity]
  #   assert_equal 10304, @gateway.result[:status_code]
  #   assert_equal "The string #{@options[:address][:zip]} in the field CreditCardPostalCode is too long. The maximum length is 9.", @gateway.result[:status_message]
  # 
  # end
  
  def parse(xml)
    h = Hash.from_xml(xml)
    symbolize_keys(h)
  end
  
  
    
end
