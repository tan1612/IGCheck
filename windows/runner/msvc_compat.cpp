// Compatibility shim for MSVC STL vectorized functions missing in MSVC < 19.38
#include <cstdint>
#include <cstring>
#include <windows.h>
#include <xtimec.h>
#include <xthreads.h>

extern "C" {

// 1. Feature flag for AVX2 wmem
int _Avx2WmemEnabled = 0;

// 2. Thread sleep
void __cdecl _Thrd_sleep_for(unsigned long ms) noexcept {
    Sleep(ms);
}

// 3. Condition variable timed wait unchecked
int __cdecl _Cnd_timedwait_for_unchecked(_Cnd_t cond, _Mtx_t mtx, unsigned int target_ms) noexcept {
    if (!cond || !mtx) return 4 /* _Thrd_error */;
    xtime xt;
    xt.sec = 0;
    xt.nsec = 0;
    xtime_get(&xt, 1 /* TIME_UTC */);
    xt.sec += static_cast<__time64_t>(target_ms / 1000);
    xt.nsec += static_cast<long>((target_ms % 1000) * 1000000);
    if (xt.nsec >= 1000000000) {
        xt.sec += 1;
        xt.nsec -= 1000000000;
    }
    return _Cnd_timedwait(cond, mtx, &xt);
}

// 4. __std_find_end_1: finds the last occurrence of [_First2, _First2 + _Count2) in [_First1, _Last1)
const void* __cdecl __std_find_end_1(
    const void* _First1, const void* _Last1, const void* _First2, size_t _Count2) noexcept {
    if (!_First1 || !_Last1 || !_First2) return _Last1;
    const uint8_t* f1 = static_cast<const uint8_t*>(_First1);
    const uint8_t* l1 = static_cast<const uint8_t*>(_Last1);
    const uint8_t* f2 = static_cast<const uint8_t*>(_First2);
    if (_Count2 == 0) return l1;
    if (static_cast<size_t>(l1 - f1) < _Count2) return l1;
    const uint8_t* res = l1;
    for (const uint8_t* cur = f1; cur + _Count2 <= l1; ++cur) {
        if (memcmp(cur, f2, _Count2) == 0) {
            res = cur;
        }
    }
    return res;
}

// 5. __std_search_1: finds the first occurrence of [_First2, _First2 + _Count2) in [_First1, _Last1)
const void* __cdecl __std_search_1(
    const void* _First1, const void* _Last1, const void* _First2, size_t _Count2) noexcept {
    const uint8_t* f1 = static_cast<const uint8_t*>(_First1);
    const uint8_t* l1 = static_cast<const uint8_t*>(_Last1);
    const uint8_t* f2 = static_cast<const uint8_t*>(_First2);
    if (_Count2 == 0) return f1;
    if (static_cast<size_t>(l1 - f1) < _Count2) return l1;
    for (const uint8_t* cur = f1; cur + _Count2 <= l1; ++cur) {
        if (memcmp(cur, f2, _Count2) == 0) {
            return cur;
        }
    }
    return l1;
}

// 6. __std_find_last_trivial_1: finds the last occurrence of _Val in [_First, _Last)
const void* __cdecl __std_find_last_trivial_1(
    const void* _First, const void* _Last, uint8_t _Val) noexcept {
    const uint8_t* f = static_cast<const uint8_t*>(_First);
    const uint8_t* l = static_cast<const uint8_t*>(_Last);
    while (l != f) {
        --l;
        if (*l == _Val) {
            return l;
        }
    }
    return static_cast<const uint8_t*>(_Last);
}

// 7. __std_min_8i: minimum element of int64_t in [_First, _Last)
int64_t __cdecl __std_min_8i(const void* _First, const void* _Last) noexcept {
    const int64_t* first = static_cast<const int64_t*>(_First);
    const int64_t* last = static_cast<const int64_t*>(_Last);
    if (first == last) return 0;
    int64_t min_val = *first++;
    while (first != last) {
        if (*first < min_val) {
            min_val = *first;
        }
        ++first;
    }
    return min_val;
}

// 8. __std_max_element_d: pointer to maximum double element in [_First, _Last)
const double* __cdecl __std_max_element_d(const double* _First, const double* _Last) noexcept {
    if (_First == _Last) return _Last;
    const double* max_ptr = _First;
    for (const double* cur = _First + 1; cur != _Last; ++cur) {
        if (*max_ptr < *cur) {
            max_ptr = cur;
        }
    }
    return max_ptr;
}

// 9. __std_remove_8: removes 8-byte elements equal to _Val from [_First, _Last)
void* __cdecl __std_remove_8(void* _First, void* _Last, uint64_t _Val) noexcept {
    uint64_t* first = static_cast<uint64_t*>(_First);
    uint64_t* last = static_cast<uint64_t*>(_Last);
    uint64_t* result = first;
    for (uint64_t* cur = first; cur != last; ++cur) {
        if (*cur != _Val) {
            *result++ = *cur;
        }
    }
    return result;
}

// 10. __std_find_first_of_trivial_pos_1: index of first character in haystack that matches any character in needle
size_t __cdecl __std_find_first_of_trivial_pos_1(
    const void* _Haystack, size_t _Haystack_length, const void* _Needle, size_t _Needle_length) noexcept {
    const uint8_t* hay = static_cast<const uint8_t*>(_Haystack);
    const uint8_t* needle = static_cast<const uint8_t*>(_Needle);
    if (_Needle_length == 0 || _Haystack_length == 0) return static_cast<size_t>(-1);

    bool table[256] = { false };
    for (size_t j = 0; j < _Needle_length; ++j) {
        table[needle[j]] = true;
    }
    for (size_t i = 0; i < _Haystack_length; ++i) {
        if (table[hay[i]]) {
            return i;
        }
    }
    return static_cast<size_t>(-1);
}

// 11. __std_find_last_of_trivial_pos_1: index of last character in haystack that matches any character in needle
size_t __cdecl __std_find_last_of_trivial_pos_1(
    const void* _Haystack, size_t _Haystack_length, const void* _Needle, size_t _Needle_length) noexcept {
    const uint8_t* hay = static_cast<const uint8_t*>(_Haystack);
    const uint8_t* needle = static_cast<const uint8_t*>(_Needle);
    if (_Needle_length == 0 || _Haystack_length == 0) return static_cast<size_t>(-1);

    bool table[256] = { false };
    for (size_t j = 0; j < _Needle_length; ++j) {
        table[needle[j]] = true;
    }
    for (size_t i = _Haystack_length; i > 0; --i) {
        if (table[hay[i - 1]]) {
            return i - 1;
        }
    }
    return static_cast<size_t>(-1);
}

} // extern "C"
