package rope

use "std::memory"
use "std::lists"

struct Node {
    left *Node
    right *Node
    priority u64
    data u8[512]
    used u64
    bytes u64
    lines u64
    local_lines u64
}

struct Rope {
    root *Node
    seed u64
}

fn size(n *Node) u64 {
    if n == nil {
        return 0
    }
    return n.bytes
}

fn breaks(n *Node) u64 {
    if n == nil {
        return 0
    }
    return n.lines
}

fn update(n *Node) {
    n.bytes = size(n.left) + n.used + size(n.right)
    n.lines = breaks(n.left) + n.local_lines + breaks(n.right)
}

fn recount(n *Node) {
    n.local_lines = 0
    i u64 := 0
    while i < n.used {
        if n.data[i] == 10 {
            n.local_lines = n.local_lines + 1
        }
        i = i + 1
    }
    update(n)
}

fn allocate(r *Rope) (*Node, error) {
    storage := memory::alloc(sizeof<Node>()) @catch err {
        return nil, err
    }
    view := slice_from_raw<Node>(storage, 1)
    view[0] = zero<Node>()
    next := r.seed * 48271 + 1
    r.seed = next - (next / 2147483647) * 2147483647
    node := &view[0]
    node.priority = r.seed
    return node, nil
}

fn destroy(n *Node) {
    if n == nil {
        return
    }
    destroy(n.left)
    destroy(n.right)
    memory::free(n)
}

fn free(r *Rope) {
    destroy(r.root)
    r.root = nil
}

fn merge(a *Node, b *Node) *Node {
    if a == nil {
        return b
    }
    if b == nil {
        return a
    }
    if a.priority < b.priority {
        a.right = merge(a.right, b)
        update(a)
        return a
    }
    b.left = merge(a, b.left)
    update(b)
    return b
}

fn split(n *Node, at u64, spare *Node) (*Node, *Node, bool) {
    if n == nil {
        return nil, nil, false
    }
    left := size(n.left)
    if at < left {
        a, b, used := split(n.left, at, spare)
        n.left = nil
        update(n)
        return a, merge(b, n), used
    }
    if at > left + n.used {
        a, b, used := split(n.right, at - left - n.used, spare)
        n.right = nil
        update(n)
        return merge(n, a), b, used
    }
    if at == left {
        a := n.left
        n.left = nil
        update(n)
        return a, n, false
    }
    if at == left + n.used {
        b := n.right
        n.right = nil
        update(n)
        return n, b, false
    }
    cut := at - left
    right := n.right
    spare.used = n.used - cut
    i u64 := 0
    while i < spare.used {
        spare.data[i] = n.data[cut + i]
        i = i + 1
    }
    n.right = nil
    n.used = cut
    recount(n)
    recount(spare)
    return n, merge(spare, right), true
}

fn compact_insert(n *Node, at u64, data u8[]) bool {
    if n == nil {
        return false
    }
    left := size(n.left)
    changed := false
    if at < left {
        changed = compact_insert(n.left, at, data)
    } elif at > left + n.used {
        changed = compact_insert(n.right, at - left - n.used, data)
    } elif n.used + len(data) <= 512 {
        offset := at - left
        i := n.used
        while i > offset {
            i = i - 1
            n.data[i + len(data)] = n.data[i]
        }
        i = 0
        while i < len(data) {
            n.data[offset + i] = data[i]
            if data[i] == 10 {
                n.local_lines = n.local_lines + 1
            }
            i = i + 1
        }
        n.used = n.used + len(data)
        changed = true
    }
    if changed {
        update(n)
    }
    return changed
}

fn replace(r *Rope, start u64, end u64, data u8[]) error {
    if start > end or end > size(r.root) {
        return error("invalid rope range")
    }
    if start == end and len(data) == 0 {
        return nil
    }
    if start == end and compact_insert(r.root, start, data) {
        return nil
    }
    inserted *Node := nil
    offset u64 := 0
    while offset < len(data) {
        node, err := allocate(r)
        if err != nil {
            destroy(inserted)
            return err
        }
        while node.used < 512 and offset < len(data) {
            node.data[node.used] = data[offset]
            node.used = node.used + 1
            offset = offset + 1
        }
        recount(node)
        inserted = merge(inserted, node)
    }
    one, spare_err := allocate(r)
    if spare_err != nil {
        destroy(inserted)
        return spare_err
    }
    two, err2 := allocate(r)
    if err2 != nil {
        destroy(inserted)
        memory::free(one)
        return err2
    }
    a, tail, used1 := split(r.root, start, one)
    removed, b, used2 := split(tail, end - start, two)
    if used1 == false {
        memory::free(one)
    }
    if used2 == false {
        memory::free(two)
    }
    destroy(removed)
    r.root = merge(merge(a, inserted), b)
    return nil
}

fn byte(r *Rope, at u64) u8 {
    n := r.root
    offset := at
    while n != nil {
        left := size(n.left)
        if offset < left {
            n = n.left
        } else {
          if offset < left + n.used {
            return n.data[offset - left]
          }
            offset = offset - left - n.used
            n = n.right
        }
    }
    return 0
}

fn copy_node(n *Node, base u64, start u64, end u64, out *lists::List<u8>) error {
    if n == nil or base >= end or base + size(n) <= start {
        return nil
    }
    copy_node(n.left, base, start, end, out) @catch err {
        return err
    }
    middle := base + size(n.left)
    i u64 := 0
    while i < n.used {
        if middle + i >= start and middle + i < end {
            lists::append<u8>(out, n.data[i]) @catch err {
                return err
            }
        }
        i = i + 1
    }
    return copy_node(n.right, middle + n.used, start, end, out)
}

fn copy(r *Rope, start u64, end u64) (lists::List<u8>, error) {
    out := lists::create<u8>()
    if start > end or end > size(r.root) {
        return out, error("invalid rope range")
    }
    lists::reserve<u8>(&out, end - start) @catch err {
        return out, err
    }
    copy_node(r.root, 0, start, end, &out) @catch err {
        lists::free<u8>(&out)
        return out, err
    }
    return out, nil
}

fn line_start(r *Rope, line u64) u64 {
    if line == 0 {
        return 0
    }
    n := r.root
    remaining := line
    offset u64 := 0
    while n != nil {
        count := breaks(n.left)
        if remaining <= count {
            n = n.left
        } else {
            remaining = remaining - count
            offset = offset + size(n.left)
            i u64 := 0
            while i < n.used {
                if n.data[i] == 10 {
                    remaining = remaining - 1
                    if remaining == 0 {
                        return offset + i + 1
                    }
                }
                i = i + 1
            }
            offset = offset + n.used
            n = n.right
        }
    }
    return size(r.root)
}

fn line_at(r *Rope, at u64) u64 {
    n := r.root
    offset := at
    result u64 := 0
    while n != nil {
        left := size(n.left)
        if offset < left {
            n = n.left
        } else {
            result = result + breaks(n.left)
            offset = offset - left
            i u64 := 0
            while i < n.used and i < offset {
                if n.data[i] == 10 {
                    result = result + 1
                }
                i = i + 1
            }
            if offset <= n.used {
                return result
            }
            offset = offset - n.used
            n = n.right
        }
    }
    return result
}
