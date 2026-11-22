"""Pydantic request and response schemas for the Hisobot Mobile APK REST API."""

from __future__ import annotations

from typing import List, Optional

from pydantic import BaseModel, Field


class LoginRequest(BaseModel):
    code: str = Field(..., min_length=4, max_length=24, description="8-digit one-time code from /apk")
    device_name: str = Field(default="Android", max_length=120)


class TelegramWebAppAuthRequest(BaseModel):
    init_data: str = Field(..., min_length=10, max_length=8192)


class LoginResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    user_id: int
    role: str
    can_write: bool
    is_admin: bool


class UserProfileResponse(BaseModel):
    user_id: int
    role: str
    can_write: bool
    is_admin: bool


class GroupConfigInfo(BaseModel):
    bound: bool
    chat_id: Optional[int] = None
    title: str = ""
    apk_post_to_group: bool = True


class CashTxOut(BaseModel):
    id: int
    session_id: int
    amount: float
    source_type: str
    note: str
    created_at: str
    time_hm: str


class CashCreateRequest(BaseModel):
    amount: float = Field(..., gt=0)
    source_type: str = Field(default="main", pattern="^(main|kassa_debt|kassa_repay)$")
    note: str = Field(default="", max_length=500)


class CashUpdateRequest(BaseModel):
    amount: Optional[float] = Field(default=None, gt=0)
    note: Optional[str] = Field(default=None, max_length=500)


class NakladnoyOut(BaseModel):
    id: int
    session_id: int
    session_seq: Optional[int] = None
    display_num: str
    supplier_name: str
    amount: float
    original_amount: Optional[float] = None
    payment_method: str
    is_debt: bool
    note: str
    has_photo: bool
    in_group: bool
    group_chat_id: Optional[int] = None
    group_message_id: Optional[int] = None
    created_at: str
    time_hm: str
    report_date: Optional[str] = None
    session_status: str = "open"


class NakladnoyUpdateRequest(BaseModel):
    supplier_name: Optional[str] = Field(default=None, min_length=1, max_length=255)
    amount: Optional[float] = Field(default=None, gt=0)
    note: Optional[str] = Field(default=None, max_length=500)
    round_amount: bool = False


class PaymentMethodRequest(BaseModel):
    payment_method: str = Field(..., pattern="^(cash|card|transfer)$")


class StatusSummaryResponse(BaseModel):
    session_id: int
    report_date: str
    session_status: str
    opening_balance: float
    main_cash_in: float
    kassa_debt_today: float
    kassa_repay_today: float
    total_available_inflow: float
    total_nakladnoy_spent: float
    total_card_spent: float
    total_transfer_spent: float
    total_debt_nakladnoy: float
    expected_cash: float
    total_kassa_debt_outstanding: float
    all_unpaid_debt_count: int
    all_unpaid_debt_total: float
    group_info: GroupConfigInfo
    cash_transactions: List[CashTxOut]
    nakladnoys: List[NakladnoyOut]


class DayCloseRequest(BaseModel):
    actual_counted_cash: float = Field(..., ge=0)


class DayCloseResponse(BaseModel):
    closed_session_id: int
    report_date: str
    expected_cash: float
    actual_counted_cash: float
    difference: float
    next_session_id: int
    next_opening_balance: float


class NasiyaCreateRequest(BaseModel):
    supplier_name: str = Field(..., min_length=1, max_length=255)
    entry_type: str = Field(..., pattern="^(debt|payment)$")
    amount: float = Field(..., gt=0)
    note: str = Field(default="", max_length=500)


class PrixodTextCreateRequest(BaseModel):
    text: str = Field(..., min_length=3)
    publish_to_group: bool = False


class SupplierConfigCreateRequest(BaseModel):
    display_name: str = Field(..., min_length=1, max_length=255)
    aliases: str = Field(default="", max_length=1000)
    default_category: str = Field(default="qarz", max_length=32)


class RoundModeUpdateRequest(BaseModel):
    round_mode: str = Field(..., pattern="^(floor_1000|nearest_1000|none)$")


