# SimpleCap helps founders create an initial cap table upon incorporation and
# handle converting SAFEs into shares during a priced round.
#
# Learn more at https://news.crunchbase.com/news/cap-tables-share-structures-valuations-oh-case-study-early-stage-funding/

class Shareholder
  attr_accessor :name, :num_shares, :percent, :price, :value

  def initialize(name, num_shares, percent, price)
    @name = name
    @num_shares = num_shares
    @percent = percent
    @price = price

    recalculate_value
  end

  def recalculate_value
    @value = @num_shares * @price
  end

  def to_s
    "#{@name} => num_shares: #{@num_shares}, percent: #{@percent}, price: #{@price}, value: #{@value}"
  end
end

class Safe
  attr_accessor :name, :paid_amount, :discount, :cap

  def initialize(name, paid_amount, discount, cap)
    @name = name
    @paid_amount = paid_amount
    @discount = discount
    @cap = cap
  end

  def to_s
    "[SAFE] #{@name} => paid_amount: #{@paid_amount}, discount: #{@discount}, cap: #{@cap}"
  end
end

class SimpleCap
  attr_accessor :shareholders, :safes

  # Part 1: Create the initial cap table
  # When incorporating a company, founders will create an initial cap table
  # including equity split amongst the founders. Any unused shares should be
  # reserved as an options pool for future employees.
  #
  # Given the following input, create an initial cap table, including the future
  # employee options pool.
  #
  # Input:
  #
  # founders_to_equity_percent: hash with a string key representing the founder's
  # name and float value for the equity percent
  # e.g. { 'Maria' => 0.50, 'Rajkumar' => 0.35 }
  #
  # total_shares: int of total shares issued on incorporation
  # e.g. 10_000_000
  #
  # price_per_share (optional): float representing USD value of each share
  # e.g. 0.001 for $0.001
  def initialize(founders_to_equity_percent, total_shares, price_per_share)
    @shareholders = []
    @safes = []

    founders_to_equity_percent.map do |name, equity_percent|
      @shareholders.push(Shareholder.new(
        name,
        (total_shares * equity_percent).round,
        equity_percent,
        price_per_share,
      ))
    end

    # Add options pool
    options_equity_percent = (1 - @shareholders.sum(&:percent)).round(4)
    @shareholders.push(Shareholder.new(
      'Options pool',
      (total_shares * options_equity_percent).round,
      options_equity_percent,
      price_per_share,
    ))
  end

  # Part 2: Add a SAFE round
  # After incorporation, founders often raise a round of funding without giving
  # equity right away. Instead, they promise to give equity to these investors
  # at a later round (known as a 'SAFE'). We want to track this promised equity
  # for future calculations.
  #
  # Since these investments are quite risky, investors typically secure
  # special terms in their SAFE acquire more equity in future rounds. We'll
  # focus on two types of terms:
  #
  # 1. Discount: investors can purchase future shares at a discounted price
  #
  # 2. Valuation Cap: investors can purchase future shares at a price based on
  #    a maximum valuation amount
  #
  # Given the following input, create SAFEs to track for the future.
  #
  # Input:
  #
  # investors_to_terms: hash with a string key representing the investor's name
  # and an array of terms shaped like example below
  # e.g. {
  #   '100X Ventures' => [
  #     1_500_000.0,  # Amount invested as a float
  #     0.20,         # 20% discount as a float
  #     12_000_000.0, # $12M valuation cap as a float
  #   ]
  # }
  #
  # Output:
  # No output required, but up to your discretion
  def add_safes(investors_to_terms)
    investors_to_terms.map { |name, terms| @safes.push(Safe.new(name, *terms)) }
  end

  # Part 3: Add a priced round
  # Eventually, the company may become successful enough to raise a priced round
  # of funding. This means that the company is valued at an initial amount,
  # called the pre-money valuation. This is used to value the existing shares
  # and deal out shares to new investors as well as SAFE investors.
  #
  # Once all shares are evaluated for new and previous investors, the value of
  # the company will change. This is called the post-money valuation.
  #
  # When adding a priced round, we'll need to:
  #
  # 1. Determine the price-per-share
  #    i.e. { pre-money valuation / total pre-existing shares }
  #
  # 2. Convert the SAFEs into shareholders. Be sure to...
  #    - If applicable, discount the price-per-share using the SAFE discount
  #    - If applicable, adjust the price-per-share by dividing with the SAFE
  #      valuation cap instead of the round's pre-money valuation
  #    - Note that, even if the price-per-share used
  #
  # 3. Convert the new investors into shareholders
  #
  # 4. Re-calculate the percentage ownership and value for each shareholder
  #    using the new total number of shares and new price-per-share
  #    - Be sure to update each shareholder to the new price-per-share
  #
  # Input:
  #
  # investors_to_paid_amounts: hash with a string key representing the investor's
  # name a float value for the investment amount
  # e.g. { 'Next Stage VC' => 4_500_000.0 }
  #
  # pre_money_valuation: float representing the company's pre-money valuation
  # e.g. 20_000_000.0
  #
  # Output:
  # Return the post-money valuation as a float
  # e.g. 98_765_432.1012
  def add_priced_round(investors_to_paid_amounts, pre_money_valuation)
    # 1. Determine the price-per-share
    total_shares = @shareholders.sum(&:num_shares)
    price_per_share = pre_money_valuation / total_shares

    # 2. Convert the SAFEs into shareholders
    @safes.map do |safe|
      # Question: What should we do if a SAFE has *both* a discount and cap?
      # Answer:   Use either the discount OR cap, whichever yields a lower price for the investor

      discounted_price_per_share = price_per_share * (1 - safe.discount)
      capped_price_per_share = if safe.cap > 0 && safe.cap < pre_money_valuation
        safe.cap / total_shares
      else
        price_per_share
      end

      # Question: What if the original price-per-share is lower than the capped price?
      # Answer:   Use whichever yields the lower price for the investor
      actual_price_per_share = [
        price_per_share,
        discounted_price_per_share,
        capped_price_per_share,
      ].min

      @shareholders.push(Shareholder.new(
        safe.name,
        (safe.paid_amount / actual_price_per_share).round,
        0.0, # to be recalculated
        price_per_share,
      ))
    end

    # 3. Convert the new investors into shareholders
    investors_to_paid_amounts.map do |name, paid_amount|
      @shareholders.push(Shareholder.new(
        name,
        (paid_amount / price_per_share).round,
        0.0, # to be recalculated
        price_per_share,
      ))
    end

    # 4. Re-calculate the percentage ownership, price, and value for each shareholder
    total_post_money_shares = @shareholders.sum(&:num_shares)
    @shareholders.map do |shareholder|
      shareholder.percent = (shareholder.num_shares / total_post_money_shares).round(4)
      shareholder.price = price_per_share
      shareholder.recalculate_value
    end

    # Return the post-money valuation as a float
    @shareholders.sum(&:value)
  end

  # Bonus discussion
  # How would you track employees? How would you handle vesting periods?
  # How would you track different terms for different investors?
end

# Part 1
sc = SimpleCap.new({
  'Jill' => 0.48,
  'Jack' => 0.32,
}, 10_000_000, 0.001)
# puts sc.shareholders

# Part 2
sc.add_safes({
  'Opaque Ventures'  => [500_000.0,   0.2,  0.0],          # 20% discount, no cap
  'BlackBox Capital' => [1_000_000.0, 0.0,  10_000_000.0], # no discount, 10M cap
  'Sandy Hills VC'   => [1_500_000.0, 0.15, 20_000_000.0], # 15% discount, 20M cap
})
# puts sc.safes

# Part 3
puts sc.add_priced_round({
  'Cormorant Ventures' => 4_000_000.0,
  'Provident Capital'  => 2_000_000.0,
  'BlackBox Capital'   => 1_000_000.0,
}, 15000000.0)
# puts sc.shareholders