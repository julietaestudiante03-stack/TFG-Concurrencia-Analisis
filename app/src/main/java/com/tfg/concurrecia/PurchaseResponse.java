package com.tfg.concurrencia;

public class PurchaseResponse {
    private boolean success;
    private String reason;

    public PurchaseResponse(boolean success, String reason) {
        this.success = success;
        this.reason = reason;
    }
    public boolean isSuccess() { return success; }
    public String getReason() { return reason; }
}