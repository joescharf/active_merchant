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
  
  def parse(xml)
    h = Hash.from_xml(xml)
    symbolize_keys(h)
  end
    
end
