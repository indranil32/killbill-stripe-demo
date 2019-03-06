require 'sinatra'
require 'killbill_client'

set :kb_url, ENV['KB_URL'] || 'http://127.0.0.1:8080'
set :publishable_key, ENV['PUBLISHABLE_KEY'] || 'pk_test_CmztJP46fhZLqKzLJGzRhfwC'

#
# Kill Bill configuration and helpers
#

KillBillClient.url = settings.kb_url

# Multi-tenancy and RBAC credentials
options = {
    :username => 'admin',
    :password => 'password',
    :api_key => 'admin',
    :api_secret => 'password'
}

# Audit log data
reason = 'Trigger by openums demo'
comment = 'Trigger by openums demo'

def create_kb_account(name, email, externalKey, currency, reason, comment, options)
  puts "for account - " + externalKey
  begin
  	existing = KillBillClient::Model::Account.find_by_external_key(externalKey,
                             false,
                             false, 
                             options)	
	existing
  rescue
	puts 'Account doesn not exist. Creating new...'
	account = KillBillClient::Model::Account.new
	account.name = name
	account.email = email
	account.external_key = externalKey
	account.currency = currency  
	account = account.create(name, reason, comment, options)
	puts 'Account created successfully'
	account
  end	  
end

def create_kb_payment_method(account, stripe_token, reason, comment, options)
  #begin
      	pm = KillBillClient::Model::PaymentMethod.new
 	pm.account_id = account.account_id
  	pm.plugin_name = 'killbill-stripe'
  	pm.plugin_info = {'token' => stripe_token}
  	pm.create(true, account.name, reason, comment, options)
 	puts 'Payment method created successfully!!'
  	pm
  #rescue
  #end
end

def create_subscription(account, pkgName, price, reason, comment, options)
  begin
	subscription = KillBillClient::Model::Subscription.new
  	subscription.account_id = account.account_id
  	# pkgList[i].product+ "-" + pkgList[i].plan + "-" + pkgList[i].priceList + "-" + pkgList[i].finalPhaseBillingPeriod;
  	#reserved-metal/reserved-metal-monthly-trial-bp/TRIAL/MONTHLY
  	array = pkgName.split("/")
  	#subscription.product_name = 
  	array.shift
  	#subscription.product_category = 'BASE'
  	subscription.plan_name = array.shift
  	#subscription.price_list = array.shift
  	#subscription.billing_period = array.shift
	#subscription.price_overrides = []

  	# For the demo to be interesting, override the trial price to be non-zero so we trigger a charge in Stripe
  	#override_trial = KillBillClient::Model::PhasePriceAttributes.new
  	#override_trial.phase_type = 'EVERGREEN'
  	#override_trial.fixed_price = price
	#subscription.price_overrides << override_trial

	subscription.create(account.name, reason, comment, nil, true, options)
 	puts 'Subscription created successfully!!'
	subscription
  rescue
 	puts 'Subscription creation error!!'
  
  end
end

#
# Sinatra handlers
#

get '/' do
  erb :index
end

post '/charge' do
  # Create an account
  account = create_kb_account(params[:name], params[:email], params[:externalKey], params[:currency], reason, comment, options)

  # Add a payment method associated with the Stripe token
  create_kb_payment_method(account, params[:stripeToken], reason, comment, options)

  # Add a subscription
  create_subscription(account, params[:package], params[:price], reason, comment, options)

  # Retrieve the invoice
  @invoice = account.invoices(true, options).first

  # And the Stripe authorization
  allTxs = @invoice.payments(true, false, 'NONE', options)
  if allTxs.nil?
	puts 'Payment error!!'
	erb :index
  else
  	transaction = allTxs.first.transactions.first
	@authorization = (transaction.properties.find { |p| p.key == 'authorization' }).value
  	erb :charge
  end  

end

__END__

@@ layout
  <!DOCTYPE html>
  <html>
  <head></head>
  <body>
    <%= yield %>
  </body>
  </html>

@@index
  <span class="image"><img src="https://drive.google.com/uc?&amp;id=0Bw8rymjWckBHT3dKd0U3a1RfcUE&amp;w=960&amp;h=480" alt="uc?&amp;id=0Bw8rymjWckBHT3dKd0U3a1RfcUE&amp;w=960&amp;h=480"></span>
  <form action="/charge" method="post">
    <article>
      <label class="amount">
        <span>Sports car, 30 days trial for only $10.00!</span>
      </label>
    </article>
    <br/>
    <input type="text" name="package" value="reserved-metal/reserved-metal-monthly-bp/DEFAULT/MONTHLY">
    <input type="text" name="externalKey" value="demo4@newremmedia.com">
    <input type="text" name="name" value="demo4@newremmedia.com">
    <input type="text" name="email" value="demo4@newremmedia.com">
    <input type="text" name="currency" value="USD">
    <input type="text" name="price" value="20">
    <script src="https://checkout.stripe.com/v3/checkout.js" class="stripe-button" data-key="<%= settings.publishable_key %>"></script>
  </form>

@@charge
  <h2>Thanks! Here is your invoice:</h2>
  <ul>
    <% @invoice.items.each do |item| %>
      <li><%= "subscription_id=#{item.subscription_id}, amount=#{item.amount}, phase=sports-monthly-trial, start_date=#{item.start_date}" %></li>
    <% end %>
  </ul>
  You can verify the payment at <a href="<%= "https://dashboard.stripe.com/test/payments/#{@authorization}" %>"><%= "https://dashboard.stripe.com/test/payments/#{@authorization}" %></a>.

