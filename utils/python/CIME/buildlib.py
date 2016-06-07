from CIME.XML.standard_module_setup import *
from CIME.case import Case
"""
buildlibx - given the caseroot and component name(cmp), build the stub component
"""

class buildlib(object):
    def __init__(self, case, model, comp):
        self.case = case
        self.model = model
        self.comp = comp

class buildxlib(buildlib):
    def buildlib(self):
        caseroot = self.case.get_value("CASEROOT")
        casetools = self.self.case.get_value("CASETOOLS")
        cimeroot = self.case.get_value("CIMEROOT")
        mach = self.case.get_value("MACH")
        libroot = self.case.get_value("LIBROOT")
        gmake_j = self.case.get_value("GMAKE_J")
        gmake = self.case.get_value("GMAKE")
        try:
            out = open('Filepath','w')
            msg = None
        except IOError, e:
            msg = str(e)

        expect(msg is None, msg)

        # Write directory list
        out.write(os.path.join(caseroot, "SourceMods", "src.%s", self.comp)
                  + "\n")
        out.write(os.path.join(cimeroot, "components", "xcpl_comps",
                               "xshare") + "\n")
        out.write(os.path.join(cimeroot, "components", "xcpl_comps",
                               self.comp, "cpl") + "\n")
        out.close()

        # generate macro values
        complib = os.path.join(libroot, "lib%s.a" % self.model)
        makefile = os.path.join(casetools, "Makefile")
        macfile = os.path.join(caseroot, "Macros.%s" % mach)

        # build 
        run_cmd("%s complib -j %d MODEL=%s COMPLIB=%s -f %s MACFILE=%s"
                % (gmake, gmake_j, self.model, complib, makefile, macfile))

