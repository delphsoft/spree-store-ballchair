module Spree
  class Promotion
    module Actions
      class CreateAdjustment < PromotionAction
        include Spree::Core::CalculatedAdjustments

        has_many :adjustments, as: :source

        delegate :eligible?, to: :promotion

        before_validation :ensure_action_has_calculator
        before_destroy :deals_with_adjustments

        # Creates the adjustment related to a promotion for the order passed
        # through options hash
        def perform(options = {})
          order = options[:order]
          return if order.promotion_credit_exists?(self)

          amount = compute_amount(calculable)
          order.adjustments.create!(
            amount: amount,
            adjustable: order,
            source: self,
            label: "#{Spree.t(:promotion)} (#{promotion.name})",
          )
        end

        # Ensure a negative amount which does not exceed the sum of the order's
        # item_total and ship_total
        def compute_amount(calculable)
          amount = self.calculator.compute(calculable).to_f.abs
          [(calculable.item_total + calculable.ship_total), amount].min * -1
        end

        private
          def ensure_action_has_calculator
            return if self.calculator
            self.calculator = Calculator::FlatPercentItemTotal.new
          end

          def deals_with_adjustments
            adjustment_scope = self.adjustments.includes(:order).references(:spree_orders)
            # For incomplete orders, remove the adjustment completely.
            adjustment_scope.where("spree_orders.completed_at IS NULL").each do |adjustment|
              adjustment.destroy
            end

            # For complete orders, the source will be invalid.
            # Therefore we nullify the source_id, leaving the adjustment in place.
            # This would mean that the order's total is not altered at all.
            adjustment_scope.where("spree_orders.completed_at IS NOT NULL").each do |adjustment|
              adjustment.update_column(:source_id, nil)
            end
          end
      end
    end
  end
end
