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
  
  
  test "remote get session ticket" do
    response = @gateway.session_ticket
      
    # Test the Response object for OK status and status code = 0
    assert_not_nil @gateway.response
    assert @gateway.response.success?
    assert_equal "OK", @gateway.response.message
    assert_equal 0, @gateway.response.params['response_code']
    
    # Session ticket is stored in Response.authorization
    assert_not_nil @gateway.response.authorization
    assert_equal @gateway.response.authorization, @gateway.response.params['raw'][:SessionTicket]  
  end
  
  test "remote get session ticket with invalid connection tkt should cause error response" do
    @invalid_gateway = QuickbooksMerchantServiceGateway.new( @qbms.update(:conntkt => 'Invalid Conn Tkt') )
    response = @invalid_gateway.session_ticket
      
    assert !@invalid_gateway.response.success?
    assert_equal 2000, @invalid_gateway.response.params['response_code']
    assert_equal "ERROR 2000: Invalid Connection Ticket", @invalid_gateway.response.message
  end
  
  test "remote create valid purchase" do
    @gateway.purchase(@amount, @credit_card, @options)
  
    assert @gateway.response.success?
    assert_equal "OK", @gateway.response.message
  
    # Check the CVV Result - M indicates Match
    assert_equal "M", @gateway.response.cvv_result['code']
  end
  
  test "remote create forced declined transaction" do
    @qbms[:test_mode_error] = "configid=10401_decline"
    @options[:address] = @address
  
    gateway = QuickbooksMerchantServiceGateway.new(@qbms)
    gateway.purchase(@amount, @credit_card, @options)
    
    assert !gateway.response.success?
    assert_equal 10401, gateway.response.params['response_code']
  end
  
  test "remote create forced cvv declined transaction" do
    @qbms[:test_mode_error] = "configid=10000_avscvdfail"
    @options[:address] = @address
  
    gateway = QuickbooksMerchantServiceGateway.new(@qbms)
    gateway.purchase(@amount, @credit_card, @options)
  
    assert !gateway.response.success?
    assert_equal 10100, gateway.response.params['response_code']
    
    assert_equal "N", gateway.response.avs_result['street_match']
    assert_equal "N", gateway.response.cvv_result['code']
  end
  
  test "remote create purchase invalid credit card" do
    @credit_card.number = "1234567890123456"
    @gateway.purchase(@amount, @credit_card, @options)
  
    assert !@gateway.response.success?
    assert_equal 10301,  @gateway.response.params['response_code']
  
  end
  
  test "remote create purchase expired credit card" do
    @credit_card.year = Time.now.year - 1
    @gateway.purchase(@amount, @credit_card, @options)
  
    assert !@gateway.response.success?
    assert_equal 10302,  @gateway.response.params['response_code']
  end
  
  test "remote create purchase with negative amount" do
    @amount = -1
    @gateway.purchase(@amount, @credit_card, @options)
  
    assert !@gateway.response.success?
    assert_equal 10300,  @gateway.response.params['response_code']
  
  end
  
  test "remote create purchase with zero amount" do
    @amount = 0
    @gateway.purchase(@amount, @credit_card, @options)
  
    assert !@gateway.response.success?
    assert_equal 10300,  @gateway.response.params['response_code']
  
  end
  
  test "remote create purchase with very large amount" do
    @amount = 1000000000000
    @gateway.purchase(@amount, @credit_card, @options)
  
    assert !@gateway.response.success?
    assert_equal 10300,  @gateway.response.params['response_code']
  
  end
  test "remote create purchase with integer amount" do
    @amount = 10
    @gateway.purchase(@amount, @credit_card, @options)
  
    assert @gateway.response.success?
    assert_equal 0,  @gateway.response.params['response_code']
  end
  
  test "remote create purchase with long address" do
    # Tests address > 30 chars (QBMS limitation)
    @address[:street1] = "1234 Really Long Street, Apartment 1234567890 South West"
    @options[:address] = @address
    @gateway.purchase(@amount, @credit_card, @options)
    
    assert !@gateway.response.success?
    assert_equal 10304,  @gateway.response.params['response_code']
  
  end
  
  test "remote create purchase with no zip" do
    @address[:zip] = ""
    @options[:address] = @address
    @gateway.purchase(@amount, @credit_card, @options)
  
    assert @gateway.response.success?
    assert_equal 0,  @gateway.response.params['response_code']
  end
  
  test "remote create and void purchase" do
    @options[:order_id] = generate_unique_id
    @gateway.purchase(@amount, @credit_card, @options)
    assert @gateway.response.success?
    assert_equal "OK", @gateway.response.message
    # Check the CVV Result - M indicates Match
    assert_equal "M", @gateway.response.cvv_result['code']
  
    auth = @gateway.response.authorization
    
    # Void the purchase:
    @options[:order_id] = generate_unique_id
    @gateway.void(auth, @options)
    assert @gateway.response.success?
    assert_equal "Refund", @gateway.response.params['void_type']
    
  end
  
  def parse(xml)
    h = Hash.from_xml(xml)
    symbolize_keys(h)
  end
  
  
  
end