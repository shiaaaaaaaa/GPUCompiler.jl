# machine code generation

function machine(cap::VersionNumber, triple::String)
    InitializeNVPTXTarget()
    InitializeNVPTXTargetInfo()
    t = Target(triple)

    InitializeNVPTXTargetMC()
    cpu = "sm_$(cap.major)$(cap.minor)"
    if cuda_driver_version >= v"9.0" && v"6.0" in ptx_support
        # in the case of CUDA 9, we use sync intrinsics from PTX ISA 6.0+
        feat = "+ptx60"
    else
        feat = ""
    end
    tm = TargetMachine(t, triple, cpu, feat)
    asm_verbosity!(tm, true)

    return tm
end

# final preparations for the module to be compiled to PTX
# these passes should not be run when e.g. compiling to write to disk.
function prepare_execution!(ctx::CompilerContext, mod::LLVM.Module)
    let pm = ModulePassManager()
        global global_ctx
        global_ctx = ctx

        global_optimizer!(pm)

        add!(pm, ModulePass("ResolveCPUReferences", resolve_cpu_references!))

        global_dce!(pm)
        strip_dead_prototypes!(pm)

        run!(pm, mod)
        dispose(pm)
    end

    return
end

# some Julia code contains references to objects in the CPU run-time,
# without actually using the contents or functionality of those objects.
#
# prime example are type tags, which reference the address of the allocated type.
# since those references are ephemeral, we can't eagerly resolve and emit them in the IR,
# but at the same time the GPU can't resolve them at run-time.
#
# this pass performs that resolution at link time.
function resolve_cpu_references!(mod::LLVM.Module)
    ctx = global_ctx::CompilerContext
    changed = false

    for f in functions(mod)
        fn = LLVM.name(f)
        if isdeclaration(f) && intrinsic_id(f) == 0 && startswith(fn, "jl_")
            # eagerly resolve the address of the binding
            address = ccall(:jl_cglobal, Any, (Any, Any), fn, UInt)
            dereferenced = unsafe_load(address)
            dereferenced = LLVM.ConstantInt(dereferenced, JuliaContext())

            function replace_bindings!(value)
                changed = false
                for use in uses(value)
                    target = user(use)
                    if isa(target, LLVM.ConstantExpr)
                        # recurse
                        changed |= replace_bindings!(target)
                    elseif isa(target, LLVM.LoadInst)
                        # resolve
                        replace_uses!(target, dereferenced)
                        unsafe_delete!(LLVM.parent(target), target)
                        # FIXME: iterator invalidation?
                        changed = true
                    end
                end
                changed
            end

            changed |= replace_bindings!(f)
        end
    end

    return changed
end

function mcgen(ctx::CompilerContext, mod::LLVM.Module, f::LLVM.Function)
    tm = machine(ctx.cap, triple(mod))

    InitializeNVPTXAsmPrinter()
    return String(emit(tm, mod, LLVM.API.LLVMAssemblyFile))
end
