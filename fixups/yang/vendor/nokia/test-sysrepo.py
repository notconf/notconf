#!/usr/bin/env python3

import argparse
import math
import time
import sysrepo


class OnlineVariance(object):
    """
    Welford's algorithm computes the sample variance incrementally.
    """

    def __init__(self, iterable=None, ddof=1):
        self.ddof, self.n, self.mean, self.M2 = ddof, 0, 0.0, 0.0
        if iterable is not None:
            for datum in iterable:
                self.include(datum)

    def include(self, datum):
        self.n += 1
        self.delta = datum - self.mean
        self.mean += self.delta / self.n
        self.M2 += self.delta * (datum - self.mean)

    @property
    def variance(self):
        return self.M2 / (self.n - self.ddof)

    @property
    def std(self):
        return math.sqrt(self.variance)


def test_sysrepo(ov, args):
    with sysrepo.SysrepoConnection() as conn:
        with conn.start_session("operational") as sess:
            for _ in range(args.n):
                start = time.perf_counter_ns()
                sess.get_data(args.path)
                end = time.perf_counter_ns()
                ov.include(end-start)


def test_netopeer(ov, args):
    from ncclient import manager
    from ncclient.xml_ import to_ele
    xml = """
<get-data xmlns='urn:ietf:params:xml:ns:yang:ietf-netconf-nmda'>
    <datastore xmlns:ds='urn:ietf:params:xml:ns:yang:ietf-datastores'>ds:operational</datastore>
    <subtree-filter>
    <state xmlns='urn:nokia.com:sros:ns:yang:sr:state'>
        <chassis>
            <chassis-class>router</chassis-class>
            <chassis-number>1</chassis-number>
            <peq>
                <peq-slot>12</peq-slot>
                <equipped-type />
            </peq>
        </chassis>
    </state>
    </subtree-filter>
</get-data>"""
    with manager.connect(host="localhost", port=830, username="admin", password="admin", hostkey_verify=False) as m:
        for _ in range(args.n):
            start = time.perf_counter_ns()
            m.dispatch(to_ele(xml))
            end = time.perf_counter_ns()
            ov.include(end-start)


def main():
    parser = argparse.ArgumentParser()
    g = parser.add_mutually_exclusive_group()
    g.add_argument('--sysrepo', action='store_true')
    g.add_argument('--netopeer', action='store_true')
    parser.add_argument('-n', default=1000, type=int)
    parser.add_argument('-p', '--path', required=True)
    args = parser.parse_args()

    ov = OnlineVariance()
    if args.sysrepo:
        test_sysrepo(ov, args)
    else:
        test_netopeer(ov, args)

    if ov.mean >= 1000:
        unit = "m"
        scale = 1000_0000
    else:
        unit = "µ"
        scale = 1000

    print(f"--- {'sysrepo' if args.sysrepo else 'netopeer'} {args.n} get_data: mean={ov.mean / scale:.6f} {unit}s; σ={ov.std / scale:.6f} {unit}s ---")

if __name__ == "__main__":
    main()
