export volatile_load, volatile_store!
export pinMode, digitalRead, digitalWrite
export delay

"""
    volatile_store!(addr::Ptr{UInt8}, v::UInt8)

Return an LLVM-based function to volatile write an 8bit value to a given address.
"""
function volatile_store!(addr::Ptr{UInt8}, v::UInt8)::Nothing
    Base.llvmcall(
        """
        %ptr = inttoptr i64 %0 to i8*
        store volatile i8 %1, i8* %ptr, align 1
        ret void
        """,
        Cvoid, Tuple{Ptr{UInt8},UInt8}, addr, v
    )
end

"""
    volatile_load(addr::Ptr{UInt8})::UInt8

Return an LLVM-based function to volatile read an 8bit value from a given address.
"""
function volatile_load(addr::Ptr{UInt8})::UInt8
    Base.llvmcall(
        """
        %ptr = inttoptr i64 %0 to i8*
        %val = load volatile i8, i8* %ptr, align 1
        ret i8 %val
        """,
        UInt8, Tuple{Ptr{UInt8}}, addr
    )
end

"""
    keep(x)

Sleep for a given x
"""
function keep(x::Int16)::Nothing
    Base.llvmcall(
        """
        call void asm sideeffect "", "" ()
        ret void
        """,
        Cvoid, Tuple{}
    )
    nothing
end

"""
    pinMode(pin::GPIO, m::PinMode)

Set a given pinmode
"""
function pinMode(pin::GPIO, m::PinMode)::Nothing
    d = volatile_load(pin.DDR)
    if m == OUTPUT
        volatile_store!(pin.DDR, d | pin.bit)
    elseif m == INPUT
        volatile_store!(pin.DDR, d & ~pin.bit)
    end
    nothing
end

"""
    digitalRead(pin::GPIO)

Read a state (high or low) of a given GPIO.
"""
function digitalRead(pin::GPIO)::PinState
    d = volatile_load(pin.DDR)
    if d & pin.bit == 0x1 ## OUTPUT
        s = volatile_load(pin.PORT)
        (s & pin.bit != 0x0) ? HIGH : LOW
    else
        s = volatile_load(pin.PIN)
        (s & pin.bit != 0x0) ? HIGH : LOW
    end
end

"""
    digitalWrite(pin::GPIO, v::PinState)

Write a given pin state (high or low) to GPIO.
"""
function digitalWrite(pin::GPIO, v::PinState)::Nothing
    s = volatile_load(pin.PORT)
    if v == HIGH
        volatile_store!(pin.PORT, s | pin.bit)
    else
        volatile_store!(pin.PORT, s & ~pin.bit)
    end
    nothing
end

"""
    delay(ms)

Delay for x ms
"""
function delay(ms::Int16)::Nothing
    for y in Int16(1):ms
        keep(y)
    end
end
