"""
AI Finance Chat router.

Provides conversation management and streaming chat endpoints.
Uses Server-Sent Events (SSE) for real-time streaming responses.
"""

import json
import uuid

from fastapi import APIRouter, Depends, HTTPException, Query, status
from fastapi.responses import StreamingResponse
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from src.app.database import get_db
from src.app.dependencies.auth import get_current_user
from src.app.dependencies.rate_limit import rate_limit
from src.app.models.chat import ChatConversation, ChatMessage
from src.app.models.user import User
from src.app.schemas.chat import (
    ChatMessageCreate,
    ChatMessageResponse,
    ChatMessagesListResponse,
    ConversationCreate,
    ConversationListResponse,
    ConversationResponse,
    ConversationUpdate,
)
from src.app.services.chat import (
    classify_intent,
    get_financial_context,
    stream_chat_response,
    DecimalEncoder,
)

router = APIRouter(prefix="/api/v1/chat", tags=["chat"])


# ─── Conversations ──────────────────────────────────────────────────


@router.post("/conversations", response_model=ConversationResponse, status_code=201)
async def create_conversation(
    data: ConversationCreate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    conversation = ChatConversation(
        user_id=current_user.id,
        title=data.title,
    )
    db.add(conversation)
    await db.commit()
    await db.refresh(conversation)
    return conversation


@router.get("/conversations", response_model=list[ConversationListResponse])
async def list_conversations(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(ChatConversation)
        .where(ChatConversation.user_id == current_user.id)
        .order_by(ChatConversation.updated_at.desc())
    )
    conversations = result.scalars().all()

    response = []
    for conv in conversations:
        # Get last message preview
        msg_result = await db.execute(
            select(ChatMessage.content)
            .where(ChatMessage.conversation_id == conv.id)
            .order_by(ChatMessage.created_at.desc())
            .limit(1)
        )
        last_msg = msg_result.scalar_one_or_none()
        preview = last_msg[:100] + "..." if last_msg and len(last_msg) > 100 else last_msg

        response.append(
            ConversationListResponse(
                id=conv.id,
                title=conv.title,
                created_at=conv.created_at,
                updated_at=conv.updated_at,
                last_message_preview=preview,
            )
        )
    return response


@router.put("/conversations/{conversation_id}", response_model=ConversationResponse)
async def update_conversation(
    conversation_id: uuid.UUID,
    data: ConversationUpdate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(ChatConversation).where(
            ChatConversation.id == conversation_id,
            ChatConversation.user_id == current_user.id,
        )
    )
    conversation = result.scalar_one_or_none()
    if not conversation:
        raise HTTPException(status_code=404, detail="Conversation not found")

    conversation.title = data.title
    await db.commit()
    await db.refresh(conversation)
    return conversation


@router.delete("/conversations/{conversation_id}", status_code=204)
async def delete_conversation(
    conversation_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(ChatConversation).where(
            ChatConversation.id == conversation_id,
            ChatConversation.user_id == current_user.id,
        )
    )
    conversation = result.scalar_one_or_none()
    if not conversation:
        raise HTTPException(status_code=404, detail="Conversation not found")

    await db.delete(conversation)
    await db.commit()


# ─── Messages ───────────────────────────────────────────────────────


@router.get(
    "/conversations/{conversation_id}/messages",
    response_model=ChatMessagesListResponse,
)
async def list_messages(
    conversation_id: uuid.UUID,
    limit: int = Query(50, ge=1, le=200),
    offset: int = Query(0, ge=0),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    # Verify ownership
    conv_result = await db.execute(
        select(ChatConversation).where(
            ChatConversation.id == conversation_id,
            ChatConversation.user_id == current_user.id,
        )
    )
    if not conv_result.scalar_one_or_none():
        raise HTTPException(status_code=404, detail="Conversation not found")

    # Get total count
    count_result = await db.execute(
        select(func.count(ChatMessage.id)).where(
            ChatMessage.conversation_id == conversation_id,
        )
    )
    total = count_result.scalar_one()

    # Get messages
    result = await db.execute(
        select(ChatMessage)
        .where(ChatMessage.conversation_id == conversation_id)
        .order_by(ChatMessage.created_at.asc())
        .offset(offset)
        .limit(limit)
    )
    messages = result.scalars().all()

    return ChatMessagesListResponse(
        items=[ChatMessageResponse.model_validate(m) for m in messages],
        total=total,
    )


_chat_send_limit = rate_limit(max_requests=20, window_seconds=60.0, bucket="chat_send")


@router.post(
    "/conversations/{conversation_id}/messages",
    dependencies=[Depends(_chat_send_limit)],
)
async def send_message(
    conversation_id: uuid.UUID,
    data: ChatMessageCreate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Send a message and stream the AI response via SSE.

    Rate-limited to 20 messages per minute per user to cap Claude API spend.
    """
    # Verify ownership
    conv_result = await db.execute(
        select(ChatConversation).where(
            ChatConversation.id == conversation_id,
            ChatConversation.user_id == current_user.id,
        )
    )
    conversation = conv_result.scalar_one_or_none()
    if not conversation:
        raise HTTPException(status_code=404, detail="Conversation not found")

    # Save user message
    user_msg = ChatMessage(
        conversation_id=conversation_id,
        role="user",
        content=data.content,
    )
    db.add(user_msg)
    await db.commit()

    # Auto-generate title from first message if none set
    if not conversation.title:
        conversation.title = data.content[:60] + ("..." if len(data.content) > 60 else "")
        await db.commit()

    # Get conversation history
    history_result = await db.execute(
        select(ChatMessage)
        .where(ChatMessage.conversation_id == conversation_id)
        .order_by(ChatMessage.created_at.asc())
    )
    history = [
        {"role": m.role, "content": m.content}
        for m in history_result.scalars().all()
    ]

    # Classify intent and get financial data
    intents = classify_intent(data.content)
    financial_context = await get_financial_context(current_user.id, intents, db)

    # Stream response via SSE
    async def event_stream():
        full_response = []
        async for chunk in stream_chat_response(
            user_message=data.content,
            conversation_history=history[:-1],  # Exclude the message we just added
            financial_context=financial_context,
            model=data.model,
        ):
            full_response.append(chunk)
            # SSE format: data: {json}\n\n
            event_data = json.dumps({"type": "text", "content": chunk})
            yield f"data: {event_data}\n\n"

        # Save the complete assistant response using a fresh session
        # (the original request session may be stale after streaming)
        complete_text = "".join(full_response)
        from src.app.database import async_session
        async with async_session() as fresh_db:
            assistant_msg = ChatMessage(
                conversation_id=conversation_id,
                role="assistant",
                content=complete_text,
                financial_context_json=financial_context,
                model_used=data.model,
                tokens_used=len(complete_text) // 4,  # Rough estimate
            )
            fresh_db.add(assistant_msg)
            await fresh_db.commit()
            await fresh_db.refresh(assistant_msg)

        # Send done event
        done_data = json.dumps({
            "type": "done",
            "message_id": str(assistant_msg.id),
            "model": data.model,
        })
        yield f"data: {done_data}\n\n"

    return StreamingResponse(
        event_stream(),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "Connection": "keep-alive",
            "X-Accel-Buffering": "no",
        },
    )
