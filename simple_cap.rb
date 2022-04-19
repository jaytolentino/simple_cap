# SimpleCap helps founders create an initial cap table upon incorporation and
# handle converting SAFEs into shares during a priced round.
#
# Learn more at https://news.crunchbase.com/news/cap-tables-share-structures-valuations-oh-case-study-early-stage-funding/

# Bonus discussion
# How would you track employees? How would you handle vesting periods?
# How would you track different terms for different investors?

class Shareholder
  attr_accessor :name, :share_class, :num_shares, :percent, :price, :value, :is_founder

  def initialize(name, num_shares, price, is_founder: false, percent: 0.0, share_class: 'Common')
    @name = name
    @share_class = share_class
    @num_shares = num_shares
    @percent = percent
    @price = price
    @is_founder = is_founder

    recalculate_price
  end

  def recalculate_price
    @value = num_shares * price
  end

  def is_common?
    share_class == 'Common'
  end
end

class SAFE
  attr_accessor :name, :paid_amount, :discount, :val_cap, :future_share_class

  def initialize(name, paid_amount, discount = 0.0, val_cap = 0, future_share_class = 'Seed Preferred')
    @name = name
    @paid_amount = paid_amount
    @discount = discount
    @val_cap = val_cap
    @future_share_class = future_share_class
  end
end

class SimpleCap
  POOL_NAME = 'Options pool'.freeze

  attr_accessor :shareholders, :safes

  # Part 1: Create the initial cap table
  # When incorporating a company, the founders will create an initial cap table
  # including equity split amongst the founders and shares kept for future
  # employees.
  #
  # Given a hash of founder names to equity percentages and a total number of
  # shares, create an initial cap table.
  #
  # Any unused percentage of shares will be saved as an options pool for future
  # employees
  def initialize(founders_to_equity_percent, total_shares, price_per_share)
    @safes = []
    @shareholders = founders_to_equity_percent.map do |founder, equity_percent|
      num_shares = total_shares * equity_percent
      Shareholder.new(
        founder,
        num_shares,
        price_per_share,
        is_founder: true,
        percent: equity_percent,
      )
    end

    # Future options (employee pool)
    pool_percent = (1 - @shareholders.sum(&:percent)).round(4)
    num_shares = (total_shares * pool_percent).to_i

    @shareholders.push(Shareholder.new(
      POOL_NAME,
      num_shares,
      price_per_share,
      percent: pool_percent,
    ))

    # TODO should include sanity check to ensure shareholder num_shares total == total_shares
  end

  # Part 2: Add a SAFE round
  # After incorporation, founders often raise a round of funding without giving
  # equity right away. Instead, they promise to give equity at a later round. We
  # want to track this promised equity to keep for future calculations.
  #
  # The advantage of a SAFE is securing special terms when converting to equity
  # in a future round:
  # 1. Discount: purchase future shares at a discount
  # 2. Valuation Cap: purchase future shares at a price based on a maximum
  #    valuation amount
  #
  # Input
  # { 'Investor Name' => [paid_amount, discount, val_cap] }
  def add_safes(investor_to_terms)
    investor_to_terms.map do |investor, terms|
      @safes.push(SAFE.new(investor, *terms))
    end
  end

  # Part 3: Add a priced round
  # Eventually, the company may become successful enough to raise a priced round
  # of funding. We want to convert the SAFE notes into equity, adding the new
  # investors and the converted investors to the cap table. Varying SAFE terms
  # will result in a separate post-money valuation once all SAFEs are converted.
  #
  # returns the updated shareholders
  def add_priced_round(investors_to_paid_amounts, pre_money_valuation, shareholders: @shareholders)
    # Price-per-share is { pre-money valuation OR valuation cap / total pre-existing shares }
    total_pre_existing_shares = @shareholders.sum(&:num_shares)
    price_per_share = (pre_money_valuation / total_pre_existing_shares).round(2)

    # Start with converting SAFEs
    @shareholders.concat(safes_to_shareholders(price_per_share, pre_money_valuation))

    # Next, let's create Shareholders for the new investor(s)
    # { 'Investor Name' => paid_amount }
    @shareholders.concat(priced_investors_to_shareholders(investors_to_paid_amounts, price_per_share))

    # Lastly, recalculate percentage using the post-money share count
    total_post_money_shares =  @shareholders.sum(&:num_shares)
    @shareholders.map do |shareholder|
      shareholder.price = price_per_share # Update since shares are now valued at a new price
      shareholder.percent = (shareholder.num_shares / total_post_money_shares).round(4)
      shareholder.recalculate_price
    end

    @shareholders
  end

  # Bonus: Founder-Friendly Rounds
  # Let's say founders want to know whether they will lose majority stake in the
  # company following a round with tentative investors.
  #
  # Create a method that takes investors and a pre-money valuation then returns
  # true if the founders will retain majority stake in the company and false
  # otherwise.
  #
  # This is a test for a potential round, so do not mutate the existing cap table
  # data.
  def is_paid_round_founder_friendly?(investors_to_paid_amounts, pre_money_valuation)
    @test_shareholders = add_priced_round(
      investors_to_paid_amounts,
      pre_money_valuation,
      shareholders: @shareholders.dup,
    )

    founder_percent = @test_shareholders.select(&:is_founder).sum(&:percent)
    puts founder_percent

    investor_percent = @test_shareholders.reject(&:is_common?).sum(&:percent)
    puts investor_percent

    founder_percent > investor_percent
  end

  private

  def safes_to_shareholders(price_per_share, pre_money_valuation)
    total_pre_existing_shares = @shareholders.sum(&:num_shares)
    @safes.map do |safe|
      # Remember to NOT use the valuation cap if it is greater than the actual
      # pre-money valuation
      actual_price_per_share = if safe.val_cap > 0 && safe.val_cap < pre_money_valuation
        (safe.val_cap / total_pre_existing_shares).round(2)
      else
        price_per_share
      end

      if safe.discount > 0
        actual_price_per_share = price_per_share * (1 - safe.discount)
      end

     Shareholder.new(
        safe.name,
        (safe.paid_amount / actual_price_per_share).round(2),
        price_per_share,
        share_class: safe.future_share_class,
      )
    end
  end

  def priced_investors_to_shareholders(investors_to_paid_amounts, price_per_share)
    investors_to_paid_amounts.map do |investor, paid_amount|
      Shareholder.new(
        investor,
        paid_amount / price_per_share,
        price_per_share,
        share_class: 'Series A Preferred',
      )
    end
  end
end

# part 1
sc = SimpleCap.new({ 'Jill' => 0.48, 'Jack' => 0.32 }, 10000000, 0.001)
# puts sc.shareholders.map { |s| "#{s.name}: #{s.share_class}, #{s.num_shares}, #{s.percent}, #{s.price}, #{s.value}" }

# part 2
sc.add_safes({
  'Opaque Ventures' => [2500000, 0.2, 0.0], # 20% discount
  'BlackBox Capital' => [2500000, 0.0, 10000000], # 10M val cap
})
# puts sc.safes.map { |s| "#{s.name}: #{s.paid_amount} @ #{s.discount * 100}% discount, #{s.val_cap} valuation cap" }

# part 3
# puts sc.add_priced_round({
#   'Cormorant Ventures' => 4000000,
#   'Provident Capital' => 2000000,
#   'BlackBox Capital' => 1000000,
# }, 15000000).sum(&:value)
# puts sc.shareholders.map { |s| "#{s.name}: #{s.share_class}, #{s.num_shares}, #{s.percent}, #{s.price}, #{s.value}" }

puts sc.is_paid_round_founder_friendly?({
  'Cormorant Ventures' => 4000000,
  'Provident Capital' => 2000000,
  'BlackBox Capital' => 1000000,
}, 15000000)