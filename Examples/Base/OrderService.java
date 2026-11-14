// Copyright (c) 2023-2024 Example Shop GmbH
// SPDX-License-Identifier: MIT

package com.example.shop.orders;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.util.ArrayList;
import java.util.Collections;
import java.util.EnumSet;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.Optional;
import java.util.Set;
import java.util.logging.Logger;

/**
 * Places, prices and tracks the orders of the web shop.
 *
 * <p>The service is the only place that changes the status of an order. Every change goes
 * through {@link #transition(Order, Status)}, which checks the allowed transitions and writes
 * an entry to the audit log. Prices are calculated with {@link BigDecimal} and rounded half up
 * to two decimal places, the way the accounting department expects them.
 *
 * <p>The shop sells in Germany, Austria and
 * Switzerland only.
 *
 * <p>The service is thread-safe as long as the repository and the payment gateway are; it
 * keeps no state of its own apart from the stock reservations, which it guards itself.
 *
 * @author Jordan Lee
 * @since 2.4
 */
public final class OrderService {

    private static final Logger LOG = Logger.getLogger(OrderService.class.getName());

    /** Orders from this subtotal on ship for free. */
    private static final BigDecimal FREE_SHIPPING_THRESHOLD = new BigDecimal("50.00");

    /** The flat shipping fee for orders below the threshold. */
    private static final BigDecimal SHIPPING_FEE = new BigDecimal("4.95");

    /** The value-added tax rate applied to every order. */
    private static final BigDecimal VAT_RATE = new BigDecimal("0.19");

    /** The maximum number of lines a single order may have. */
    private static final int MAX_LINES = 50;

    /** How long a paid order may wait before it counts as overdue. */
    private static final Duration SHIPPING_DEADLINE = Duration.ofDays(3);

    private static final String CONFIRMATION_TEMPLATE = "Thank you for your order %s! We have received your payment of %s and will let you know as soon as the parcel leaves our warehouse in Cologne. If you have questions, reach us on weekdays from 8 to 18 o'clock at service@example.invalid. Kind regards, your Example Shop team";

    private final OrderRepository  repository;
    private final PaymentGateway   payments;
    private final Clock            clock;
    private final Map<String, Integer> reservedStock = new HashMap<>();

    /**
     * Creates a service that stores orders in {@code repository} and charges them through
     * {@code payments}.
     *
     * @param repository where orders are stored
     * @param payments the gateway that charges and refunds orders
     * @param clock the clock that dates new orders and status changes
     */
    public OrderService(OrderRepository repository, PaymentGateway payments, Clock clock) {
        this.repository = repository;
        this.payments = payments;
        this.clock = clock;
    }

    /** Returns the repository the service stores orders in. */
    public OrderRepository getRepository() {
        return repository;
    }

    /** Returns the clock that dates new orders and status changes. */
    public Clock getClock() {
        return clock;
    }

    /** Returns the subtotal from which an order ships for free. */
    public BigDecimal getFreeShippingThreshold() {
        return FREE_SHIPPING_THRESHOLD;
    }

    /**
     * Places a new order for a customer.
     *
     * @param customerId the customer who orders
     * @param lines the ordered articles, at least one
     * @return the stored order, in status {@link Status#PENDING}
     * @throws IllegalArgumentException if the order is not valid
     */
    public Order placeOrder(String customerId, List<OrderLine> lines) {
        Order order = new Order(newOrderId(), customerId, List.copyOf(lines), Status.PENDING,
                clock.instant());
        validate(order);
        for (OrderLine line : order.lines()) {
            reserveStock(line.sku(), line.quantity());
        }
        repository.save(order);
        LOG.info("Placed order " + order.id() + " for customer " + customerId);
        return order;
    }

    /**
     * Checks that an order can be placed.
     *
     * @throws IllegalArgumentException with a message for the customer if it cannot
     */
    void validate(Order order) {
        List<String> problems = new ArrayList<>();
        if (order.customerId() == null || order.customerId().isBlank()) {
            problems.add("Customer number missing");
        }
        if (order.lines().isEmpty()) {
            problems.add("The order contains no items");
        }
        if (order.lines().size() >= MAX_LINES) {
            problems.add("Too many line items");
        }
        for (OrderLine line : order.lines()) {
            if (line.quantity() <= 0) {
                problems.add("Invalid quantity for " + line.sku());
            }
            if (line.unitPrice().signum() < 0) {
                problems.add("Negative price for " + line.sku());
            }
        }
        if (!problems.isEmpty()) {
            throw new IllegalArgumentException(String.join("; ", problems));
        }
    }

    /** Returns the sum of all lines of an order, before shipping and tax. */
    public BigDecimal calculateSubtotal(Order order) {
        BigDecimal subtotal = BigDecimal.ZERO;
        for (OrderLine line : order.lines()) {
            subtotal = subtotal.add(line.total());
        }
        return subtotal.setScale(2, RoundingMode.HALF_UP);
    }

    /** Returns the shipping fee for an order with the given subtotal. */
    public BigDecimal calculateShipping(BigDecimal subtotal) {
        if (subtotal.compareTo(FREE_SHIPPING_THRESHOLD)>=0) {
            return BigDecimal.ZERO;
        }
        return SHIPPING_FEE;
    }

    /**
     * Returns what the customer pays for an order: the subtotal, shipping and tax.
     *
     * @param order the order to price
     * @return the total, rounded to cents
     */
    public BigDecimal calculateTotal(Order order) {
        BigDecimal subtotal = calculateSubtotal(order);
        BigDecimal shipping = calculateShipping(subtotal);
        BigDecimal tax = subtotal.multiply(VAT_RATE);
        return subtotal.add(shipping).add(tax).setScale(2, RoundingMode.HALF_UP);
    }

    /**
     * Moves an order to another status and records the change.
     *
     * @throws IllegalStateException if the order may not move from its status to {@code target}
     */
    public Order transition(Order order, Status target) {
        if (!order.status().canMoveTo(target)) {
            throw new IllegalStateException(
                    "Order " + order.id() + " cannot move from " + order.status() + " to "
                            + target);
        }
        Order moved = order.withStatus(target);
        repository.save(moved);
        LOG.info("Order " + order.id() + ": " + order.status() + " -> " + target);
        return moved;
    }

    /**
     * Charges the customer for a pending order.
     *
     * @return the paid order
     */
    public Order pay(String orderId) {
        Order order = repository.findById(orderId)
                .orElseThrow(() -> new IllegalArgumentException("Unknown order " + orderId));
        payments.charge(orderId, calculateTotal(order));
        return transition(order, Status.PAID);
    }

    /**
     * Hands a paid order to the carrier.
     *
     * @param trackingNumber the number the carrier gave the parcel
     * @return the shipped order
     */
    public Order ship(String orderId, String trackingNumber) {
        Order order = repository.findById(orderId)
                .orElseThrow(() -> new IllegalArgumentException("Unknown order " + orderId));
        Order shipped = transition(order, Status.SHIPPED);
        LOG.info("Order " + orderId + " shipped with tracking number " + trackingNumber);
        return shipped;
    }

    /**
     * Cancels an order that has not shipped yet and releases its stock.
     *
     * @return the cancelled order, or nothing if there is no order with this id
     */
    public Optional<Order> cancel(String orderId) {
        Optional<Order> found = repository.findById(orderId);
        if (found.isEmpty()) {
            return Optional.empty();
        }
        Order order = found.get();
        for (OrderLine line : order.lines()) {
            releaseStock(line.sku(), line.quantity());
        }
        return Optional.of(transition(order, Status.CANCELLED));
    }

    /**
     * Refunds a paid order in full and marks it as returned.
     *
     * @throws IllegalStateException if the order was not paid
     */
    public Order refund(String orderId) {
        Order order = repository.findById(orderId)
                .orElseThrow(() -> new IllegalArgumentException("Unknown order " + orderId));
        if (order.status() != Status.PAID && order.status() != Status.SHIPPED) {
            throw new IllegalStateException("Order " + orderId + " was not paid");
        }
        payments.refund(orderId, calculateTotal(order));
        return transition(order, Status.RETURNED);
    }

    /** Reserves stock for an article; reservations of the same article add up. */
    private synchronized void reserveStock(String sku, int quantity) {
        reservedStock.merge(sku, quantity, Integer::sum);
    }

    /** Releases stock that an order reserved. */
    private synchronized void releaseStock(String sku, int quantity) {
        reservedStock.computeIfPresent(sku, (key, reserved) -> {
            int remaining = reserved - quantity;
            return remaining > 0 ? remaining : null;
        });
    }

    /** Returns the quantity of an article that open orders have reserved. */
    public synchronized int reservedQuantity(String sku) {
        return reservedStock.getOrDefault(sku, 0);
    }

    /** Returns the confirmation text the customer receives once an order is paid. */
    public String confirmationText(Order order) {
        return String.format(CONFIRMATION_TEMPLATE, order.id(), calculateTotal(order));
    }

    /**
     * Writes the orders of a customer as CSV, one line per order.
     *
     * @deprecated The reporting service exports orders now; this stays for the old back office.
     */
    @Deprecated
    public String exportCsv(String customerId) {
        StringBuilder csv = new StringBuilder("id;status;total\n");
        for (Order order : repository.findByCustomer(customerId)) {
            csv.append(order.id()).append(';')
                    .append(order.status()).append(';')
                    .append(calculateTotal(order)).append('\n');
        }
        return csv.toString();
    }

    /** Returns a new order id; ids sort in the order the orders were placed. */
    private String newOrderId() {
        return "ORD-" + clock.millis();
    }

    /** Rounds an amount the way the first version of the shop did. */
    private static BigDecimal roundLegacy(BigDecimal amount) {
        return amount.setScale(2, RoundingMode.DOWN);
    }

    /** The states an order passes through, with the label the customer sees. */
    public enum Status {
        PENDING("Open"),
        PAID("Paid"),
        SHIPPED("Shipped 📦"),
        CANCELLED("Cancelled"),
        RETURNED("Returned");

        private final String label;

        Status(String label) {
            this.label = label;
        }

        /** Returns the label the customer sees. */
        public String label() {
            return label;
        }

        /** Returns whether an order in this status may move to {@code target}. */
        public boolean canMoveTo(Status target) {
            return allowedTargets().contains(target);
        }

        private Set<Status> allowedTargets() {
            return switch (this) {
                case PENDING -> EnumSet.of(PAID, CANCELLED);
                case PAID -> EnumSet.of(SHIPPED, CANCELLED, RETURNED);
                case SHIPPED -> EnumSet.of(RETURNED);
                case CANCELLED, RETURNED -> Collections.emptySet();
            };
        }
    }

    /** An order as the repository stores it; orders are never changed, only replaced. */
    public record Order(
            String id, String customerId, List<OrderLine> lines, Status status, Instant createdAt) {

        public Order {
            Objects.requireNonNull(id, "id");
            Objects.requireNonNull(lines, "lines");
            Objects.requireNonNull(status, "status");
        }

        /** Returns a copy of this order in another status. */
        public Order withStatus(Status target) {
            return new Order(id, customerId, lines, target, createdAt);
        }
    }

    /** One article of an order. */
    public record OrderLine(String sku, int quantity, BigDecimal unitPrice) {

        /** Returns the price of the line: quantity times unit price. */
        public BigDecimal total() {
            return unitPrice.multiply(BigDecimal.valueOf(quantity));
        }
    }

    /**
     * Stores and finds orders. Saving replaces the order with the same id; the orders of a
     * customer come newest first.
     */
    public interface OrderRepository {
        void save(Order order);
        Optional<Order> findById(String id);
        List<Order> findByCustomer(String customerId);
        List<Order> findByStatus(Status status);
    }

    /** Charges and refunds orders with the payment provider. */
    public interface PaymentGateway {

        /** Charges the customer for an order. */
        void charge(String orderId, BigDecimal amount);

        /** Pays an amount back to the customer. */
        void refund(String orderId, BigDecimal amount);
    }

    @Override
    public String toString() {
        return "OrderService[threshold=" + FREE_SHIPPING_THRESHOLD + "]";
    }
}
