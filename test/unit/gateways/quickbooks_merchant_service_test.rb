require File.dirname(__FILE__) + '/../../test_helper'

class QuickbooksMerchantServiceTest < Test::Unit::TestCase

  # Update this structure with a real test mode gateway
  QBMS = {
    :test_gw => {
      :mode => :test,
      :url => 'https://login.ptc.quickbooks.com/j/qbn/sdkapp/confirm?appid=103549521&serviceid=1002',
      :cert => 'qbms-test.crt',
      :cn => 'cn.example.com',
      :applogin => 'app.example.com',
      :conntkt => 'TGT-XX-XXXXXXXXXXXXXXXXXXXXXX'
    },
    :authorized_ips => ['206.154.105.61', '206.154.102.244', '206.154.102.247'],
    :test_gw => appid
  }
  
  def setup
    # Test from RAILS_ROOT:
    # ruby vendor/plugins/active_merchant/test/unit/gateways/QuickbooksMerchantService_test.rb 
    @cert = cert = File.read("config/#{QBMS[:test_gw][:cert]}")
    @gateway = QuickbooksMerchantServiceGateway.new(  :pem => @cert,
                                                      :gw_mode => QBMS[:test_gw][:mode],
                                                      :applogin => QBMS[:test_gw][:applogin],
                                                      :conntkt => QBMS[:test_gw][:conntkt]
                                                    )

    @credit_card = CreditCard.new(:number => "4242424242424242",
                                  :month => Time.now.month,
                                  :year => Time.now.year,
                                  :verification_value => "123",
                                  :first_name => "John",
                                  :last_name => "Doe")
    @amount = "1.00"
    
    @address = { :name => "John Doe",
                 :address => "1234 Main St.",
                 :city => "Boulder",
                 :state => "CO",
                 :zip => "80301"
    }
    
    @options = { 
      :address => @address
    }
  end
  
  def test_gateway_mode_test
    @gateway = QuickbooksMerchantServiceGateway.new(  :pem => @cert,
                                                      :gw_mode => :test,
                                                      :applogin => QBMS[:test_gw][:applogin],
                                                      :conntkt => QBMS[:test_gw][:conntkt]
                                                    )
    assert @gateway.test?
    assert !@gateway.debug?
    assert !@gateway.production?
  end
  
  def test_gateway_mode_debug
    @gateway = QuickbooksMerchantServiceGateway.new(  :pem => @cert,
                                                      :gw_mode => :debug,
                                                      :applogin => QBMS[:test_gw][:applogin],
                                                      :conntkt => QBMS[:test_gw][:conntkt]
                                                    )
    assert @gateway.debug?
    assert !@gateway.test?
    assert !@gateway.production?
  end
  
  def test_gateway_mode_production
    @gateway = QuickbooksMerchantServiceGateway.new(  :pem => @cert,
                                                      :gw_mode => :production,
                                                      :applogin => QBMS[:test_gw][:applogin],
                                                      :conntkt => QBMS[:test_gw][:conntkt]
                                                    )
    assert @gateway.production?
    assert !@gateway.debug?
    assert !@gateway.test?
  end
  
  def test_create_session_ticket
    session_ticket = @gateway.signon_app_cert_rq
    st_hsh = Hash.from_xml(session_ticket)
    assert_equal QBMS[:test_gw][:conntkt], st_hsh["QBMSXML"]["SignonMsgsRq"]["SignonAppCertRq"]["ConnectionTicket"]
    assert_equal QBMS[:test_gw][:applogin], st_hsh["QBMSXML"]["SignonMsgsRq"]["SignonAppCertRq"]["ApplicationLogin"]
  end
  
  def test_get_session_ticket
    session_ticket = @gateway.signon_app_cert_rq
    @gateway.commit('session_ticket', session_ticket)
      
    assert_not_nil @gateway.result
    assert_equal "INFO", @gateway.result[:status_severity]
    assert_equal 0, @gateway.result[:status_code]
  
    assert_not_nil @gateway.result[:session_ticket]
    assert_equal @gateway.result[:session_ticket], @gateway.res_hsh["QBMSXML"]["SignonMsgsRs"]["SignonAppCertRs"]["SessionTicket"]
  end
  
  def test_get_session_ticket_with_invalid_conn_tkt
    @invalid_gateway = QuickbooksMerchantServiceGateway.new(
                                                      :pem => @cert,
                                                      :test => QBMS[:test_gw][:mode],
                                                      :applogin => QBMS[:test_gw][:applogin],
                                                      :conntkt => 'Invalid Conn Tkt'
                                                    )
    session_ticket = @invalid_gateway.signon_app_cert_rq
    @invalid_gateway.commit('session_ticket', session_ticket)
      
    assert_equal "ERROR", @invalid_gateway.result[:status_severity]
    assert_equal 2000, @invalid_gateway.result[:status_code]
    assert_equal "Exception resource file missing: platform_ex locale: en_US id: ACCOUNT-5006", @invalid_gateway.result[:status_message]
  end
  
  
  #############################################################################
  # PURCHASE TESTS
  #############################################################################
  
  def test_create_purchase_request
    ccreq = @gateway.customer_credit_card_charge_rq(@amount, @credit_card, @options)
    ccreq_h = Hash.from_xml(ccreq)
    
    assert_not_nil ccreq_h
    assert_equal @credit_card.number, ccreq_h["QBMSXML"]["QBMSXMLMsgsRq"]["CustomerCreditCardChargeRq"]["CreditCardNumber"]
  end
  
  def test_create_valid_purchase
    @gateway.purchase(@amount, @credit_card, @options)
  
    assert_equal "INFO", @gateway.result[:status_severity]
    assert_equal 0, @gateway.result[:status_code]
  
    assert_equal "Pass", @gateway.result[:charge_response][:card_security_code_match]
  end

  def test_create_declined_transaction
    @gateway = QuickbooksMerchantServiceGateway.new(  :pem => @cert,
                                                      :gw_mode => :test,
                                                      :applogin => QBMS[:test_gw][:applogin],
                                                      :conntkt => QBMS[:test_gw][:conntkt],
                                                      :test_mode_error => "configid=10401_decline" # Card Declined
                                                    )
    @gateway.purchase(@amount, @credit_card, @options)

    assert_equal "ERROR", @gateway.result[:status_severity]
    assert_equal 10401, @gateway.result[:status_code]
  end

  def test_create_cvv_declined_transaction
    @gateway = QuickbooksMerchantServiceGateway.new(  :pem => @cert,
                                                      :gw_mode => :test,
                                                      :applogin => QBMS[:test_gw][:applogin],
                                                      :conntkt => QBMS[:test_gw][:conntkt],
                                                      :test_mode_error => "configid=10000_avscvdfail" # CVD FAIL
                                                    )
    @gateway.purchase(@amount, @credit_card, @options)

    assert_equal "WARN", @gateway.result[:status_severity]
    assert_equal 10100, @gateway.result[:status_code]
  end

  
  def test_create_valid_purchase_no_session_ticket
    ccreq = @gateway.customer_credit_card_charge_rq(@amount, @credit_card, @options)
    @gateway.commit('sale', ccreq)
  
    assert_equal "ERROR", @gateway.result[:status_severity]
    assert_equal 2000, @gateway.result[:status_code]
    assert_equal "Invalid signon", @gateway.result[:status_message]
  end
  
  def test_create_purchase_invalid_credit_card
    @credit_card.number = "1234567890123456"
    @gateway.purchase(@amount, @credit_card, @options)
  
    assert_equal "ERROR", @gateway.result[:status_severity]
    assert_equal 10301, @gateway.result[:status_code]
    assert_equal "This credit card number is invalid.", @gateway.result[:status_message]
  
  end
  
  def test_create_purchase_expired_cc
    @credit_card.year = Time.now.year - 1
    @gateway.purchase(@amount, @credit_card, @options)
  
    assert_equal "ERROR", @gateway.result[:status_severity]
    assert_equal 10302, @gateway.result[:status_code]
    assert_equal "An error occurred while validating the date value #{Time.now.month}/#{Time.now.year - 1} in the field ExpirationMonth/ExpirationYear.", @gateway.result[:status_message]
  
  end
  
  def test_create_purchase_negative_amount
    @amount = -1
    @gateway.purchase(@amount, @credit_card, @options)
  
    assert_equal "ERROR", @gateway.result[:status_severity]
    assert_equal 10300, @gateway.result[:status_code]
    assert_equal "An error occurred while converting the amount #{@amount} in the field Amount.", @gateway.result[:status_message]
  
  end
  def test_create_purchase_zero_amount
    @amount = 0
    @gateway.purchase(@amount, @credit_card, @options)
  
    assert_equal "ERROR", @gateway.result[:status_severity]
    assert_equal 10300, @gateway.result[:status_code]
    assert_equal "An error occurred while converting the amount #{@amount} in the field Amount.", @gateway.result[:status_message]
  
  end
  
  def test_create_purchase_very_large_amount
    @amount = 1000000000000
    @gateway.purchase(@amount, @credit_card, @options)
  
    assert_equal "ERROR", @gateway.result[:status_severity]
    assert_equal 10300, @gateway.result[:status_code]
    assert_equal "An error occurred while converting the amount #{@amount} in the field Amount.", @gateway.result[:status_message]
  
  end
  
  def test_create_purchase_amount_integer
    @amount = 10
    @gateway.purchase(@amount, @credit_card, @options)
  
    assert_equal "INFO", @gateway.result[:status_severity]
    assert_equal 0, @gateway.result[:status_code]
  end
  
  def test_create_purchase_long_address
    # Tests address > 30 chars (QBMS limitation)
    @options[:address][:address] = "1234 Really Long Street, Apartment 1234567890 South West"
    @gateway.purchase(@amount, @credit_card, @options)
  
    assert_equal "ERROR", @gateway.result[:status_severity]
    assert_equal 10304, @gateway.result[:status_code]
    assert_equal "The string #{@options[:address][:address]} in the field CreditCardAddress is too long. The maximum length is 30.", @gateway.result[:status_message]
  
  end
  
  def test_create_purchase_no_zip
    @options[:address][:zip] = ""
    @gateway.purchase(@amount, @credit_card, @options)
  
    assert_equal "INFO", @gateway.result[:status_severity]
    assert_equal 0, @gateway.result[:status_code]
  
  end
  
  def test_create_purchase_invalid_zip
    @options[:address][:zip] = "123"
    @gateway.purchase(@amount, @credit_card, @options)
  
    assert_equal "INFO", @gateway.result[:status_severity]
    assert_equal 0, @gateway.result[:status_code]
  
  end
  
  def test_create_purchase_invalid_long_zip
    @options[:address][:zip] = "123456789012345"
    @gateway.purchase(@amount, @credit_card, @options)
  
    assert_equal "ERROR", @gateway.result[:status_severity]
    assert_equal 10304, @gateway.result[:status_code]
    assert_equal "The string #{@options[:address][:zip]} in the field CreditCardPostalCode is too long. The maximum length is 9.", @gateway.result[:status_message]
  
  end
    
end
